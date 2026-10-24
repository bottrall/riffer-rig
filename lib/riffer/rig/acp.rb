# frozen_string_literal: true

require 'acp/sdk'
require 'time'

# The ACP tier: Runtime events reach the client only through this adapter's
# mapping, so nothing else in rig may translate an event into an ACP type.
class Riffer::Rig::ACP
  AGENT_NAME = 'riffer' #: String
  AGENT_TITLE = 'Riffer' #: String

  SESSION_EXTENSION = 'acp' #: String

  # @rbs @input: IO
  # @rbs @output: IO
  # @rbs @env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs @home: String
  # @rbs @cwd: String
  # @rbs @build: ^(String, Riffer::Rig::Hosts::_Host, Hash[String, Riffer::Rig::Mcp::Declaration]) -> Riffer::Rig::Runtime
  # @rbs @adopt: (^(String) -> Riffer::Rig::Runtime?)?
  # @rbs @client: ::ACP::AgentConnection::Client?
  # @rbs @sessions: Hash[String, Riffer::Rig::Runtime]
  # @rbs @hosts: Hash[String, Riffer::Rig::ACP::Host]
  # @rbs @owned: Array[Riffer::Rig::Runtime]
  # @rbs @lock: Thread::Mutex

  # @rbs input: IO
  # @rbs output: IO
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs cwd: String
  # @rbs build: (^(String, Riffer::Rig::Hosts::_Host, Hash[String, Riffer::Rig::Mcp::Declaration]) -> Riffer::Rig::Runtime)?
  # @rbs adopt: (^(String) -> Riffer::Rig::Runtime?)?
  # @rbs return: Riffer::Rig::ACP
  def self.for(input:, output:, env:, home:, cwd:, build: nil, adopt: nil)
    new(input: input, output: output, env: env, home: home, cwd: cwd, build: build, adopt: adopt)
  end

  # @rbs cwd: String
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs servers: Hash[String, Riffer::Rig::Mcp::Declaration]
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs return: Riffer::Rig::Runtime
  def self.build_runtime(cwd, host, servers, env:, home:)
    Riffer::Rig::Loader.runtime(
      cwd: cwd, host: host, env: env, home: home, extra_extensions: session_extensions(servers)
    )
  end

  # @rbs servers: Hash[String, Riffer::Rig::Mcp::Declaration]
  # @rbs return: Array[Riffer::Rig::Extension]
  def self.session_extensions(servers)
    return [] if servers.empty?

    # A synthetic extension, so a reload rebuild re-declares the servers and an
    # extension's same-name declaration replaces them with the usual notify.
    extension = Riffer::Rig::Extension.new(SESSION_EXTENSION) do |rig|
      servers.each { |name, server| rig.mcp(name, command: server.command, args: server.args, env: server.env) }
    end
    [extension]
  end

  # @rbs input: IO
  # @rbs output: IO
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs cwd: String
  # @rbs build: (^(String, Riffer::Rig::Hosts::_Host, Hash[String, Riffer::Rig::Mcp::Declaration]) -> Riffer::Rig::Runtime)?
  # @rbs adopt: (^(String) -> Riffer::Rig::Runtime?)?
  # @rbs return: void
  def initialize(input:, output:, env:, home:, cwd:, build: nil, adopt: nil)
    @input = input
    @output = output
    @env = env
    @home = home
    @cwd = cwd
    @build = build || lambda do |cwd, host, servers|
      own(self.class.build_runtime(cwd, host, servers, env: @env, home: @home))
    end
    @adopt = adopt
    @client = nil
    @sessions = {}
    @hosts = {}
    @owned = []
    @lock = Mutex.new
  end

  # @rbs &block: ? (::ACP::AgentConnection) -> void
  # @rbs return: Integer
  def run
    connection = ::ACP::AgentConnection.new(
      transport: ::ACP::Transport::Stdio.new(input: @input, output: @output),
      capabilities: ::ACP::Types::AgentCapabilities.new(
        load_session: true,
        session_capabilities: ::ACP::Types::SessionCapabilities.new(list: ::ACP::Types::SessionListCapabilities.new)
      ),
      agent_info: ::ACP::Types::Implementation.new(name: AGENT_NAME, version: Riffer::Rig::VERSION, title: AGENT_TITLE)
    ) do |client|
      @client = client
      self
    end
    connection.start.join
    yield connection if block_given?
    0
  ensure
    # Background jobs run in process groups of their own, so only closing
    # their Runtime stops them outliving this process. A turn still running is
    # not waited for, so it is cancelled first to stop it starting another.
    @lock.synchronize { @owned.dup }.each do |runtime|
      runtime.cancel
      runtime.close
    end
  end

  # @rbs request: ::ACP::Types::NewSessionRequest
  # @rbs return: (::ACP::Types::NewSessionResponse | ::ACP::RequestError)
  def new_session(request)
    host = Riffer::Rig::ACP::Host.new(client: client)
    servers = declarations(request.mcp_servers, host)
    runtime = announcing_job_exits(@build.call(request.cwd, host, servers), host)
    @lock.synchronize do
      @sessions[runtime.id] = runtime
      @hosts[runtime.id] = host
    end
    ::ACP::Types::NewSessionResponse.new(session_id: runtime.id)
  rescue StandardError => e
    internal_error(e)
  end

  # @rbs request: ::ACP::Types::PromptRequest
  # @rbs return: (::ACP::Types::PromptResponse | ::ACP::RequestError)
  def prompt(request)
    runtime = session(request.session_id)
    return ::ACP::RequestError.resource_not_found unless runtime

    commands = available_commands(runtime).to_set(&:to_h)
    # A command that runs no turn sends no turn_end.
    stop_reason = :completed
    dispatch(runtime, Riffer::Rig::ACP::Mapper.prompt_text(request.prompt)) do |event|
      case event
      when Riffer::Rig::Events::TurnEnd then stop_reason = event.stop_reason
      end
      update = Riffer::Rig::ACP::Mapper.update_for(event)
      client.update(request.session_id, update) if update
    end
    # A reload in the dispatch, by /reload or the automatic check, can change
    # the commands; its rebuild also reorders them, which is no change.
    reloaded = available_commands(runtime)
    client.available_commands(request.session_id, reloaded) unless reloaded.to_set(&:to_h) == commands
    ::ACP::Types::PromptResponse.new(stop_reason: Riffer::Rig::ACP::Mapper.stop_reason_of(stop_reason))
  rescue Riffer::Rig::Runtime::BusyError
    ::ACP::RequestError.new(
      code: ::ACP::RequestError::INVALID_REQUEST,
      message: 'a prompt is already running on this session; wait for it to finish or cancel it'
    )
  rescue StandardError => e
    internal_error(e)
  end

  # @rbs request: ::ACP::Types::LoadSessionRequest
  # @rbs return: (::ACP::Types::LoadSessionResponse | ::ACP::RequestError)
  def load_session(request)
    host = Riffer::Rig::ACP::Host.new(client: client)
    loader = Riffer::Rig::Loader.new(cwd: request.cwd, host: host, env: @env, home: @home)
    runtime = adopted(request.session_id) || resumed(loader, request, host)
    return ::ACP::RequestError.resource_not_found unless runtime

    # A client need not answer a question while its own session/load is
    # pending, and acp-sdk never times a request out, so the host takes the
    # session id only once the build can no longer ask one.
    host.session_id = request.session_id
    @lock.synchronize { @sessions[request.session_id] = runtime }
    loader.messages(request.session_id)
          .filter_map { |message| Riffer::Rig::ACP::Mapper.replay_of(message) }
          .each { |update| client.update(request.session_id, update) }
    client.available_commands(request.session_id, available_commands(runtime))
    ::ACP::Types::LoadSessionResponse.new
  rescue StandardError => e
    internal_error(e)
  end

  # @rbs request: ::ACP::Types::ListSessionsRequest
  # @rbs return: (::ACP::Types::ListSessionsResponse | ::ACP::RequestError)
  def list_sessions(request)
    loader = Riffer::Rig::Loader.new(
      cwd: request.cwd || @cwd,
      host: Riffer::Rig::Hosts::Null.new,
      env: @env,
      home: @home
    )
    headers = request.cwd ? loader.list : loader.list(all: true)
    sessions = headers.map do |header|
      ::ACP::Types::SessionInfo.new(
        session_id: header.id,
        cwd: header.cwd,
        title: header.title,
        updated_at: header.updated&.utc&.iso8601
      )
    end
    ::ACP::Types::ListSessionsResponse.new(sessions: sessions)
  rescue StandardError => e
    internal_error(e)
  end

  # Runs on the transport's reader thread, so it asks the turn to stop and
  # never waits for it.
  # @rbs notification: ::ACP::Types::CancelNotification
  # @rbs return: void
  def cancel(notification)
    session(notification.session_id)&.cancel
  end

  # Runs after the session/new reply, so the client knows the id before any
  # update for it arrives: the build-time notifies flush here, then the
  # commands go out.
  # @rbs response: ::ACP::Types::NewSessionResponse
  # @rbs return: void
  def session_created(response)
    id = response.session_id
    # @type var found: [Riffer::Rig::ACP::Host?, Riffer::Rig::Runtime?]
    found = @lock.synchronize { [@hosts[id], @sessions[id]] }
    host, runtime = found
    return unless host && runtime

    host.session_id = id
    client.available_commands(id, available_commands(runtime))
  end

  private

  # @rbs return: ::ACP::AgentConnection::Client
  def client
    @client or raise 'ACP agent used before ::ACP::AgentConnection.start built it'
  end

  # @rbs id: String
  # @rbs return: Riffer::Rig::Runtime?
  def session(id)
    @lock.synchronize { @sessions[id] }
  end

  # @rbs error: StandardError
  # @rbs return: ::ACP::RequestError
  def internal_error(error)
    ::ACP::RequestError.new(code: ::ACP::RequestError::INTERNAL_ERROR, message: Riffer::Rig::Runtime::ErrorMessage.of(error))
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs text: String
  # @rbs &: (::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void
  # @rbs return: void
  def dispatch(runtime, text, &)
    command = Riffer::Rig::Command::INVOCATION.match(text)
    command ? runtime.run_command(command[1].to_s, command[2].to_s, &) : runtime.prompt(text, &)
  end

  # @rbs id: String
  # @rbs return: Riffer::Rig::Runtime?
  def adopted(id)
    runtime = @adopt&.call(id)
    # The Loader that built the Runtime holds this same host, so it is
    # re-pointed in place rather than replaced.
    case (host = runtime&.host&.host)
    when Riffer::Rig::ACP::Host then host.client = client
    end
    runtime
  end

  # @rbs loader: Riffer::Rig::Loader
  # @rbs request: ::ACP::Types::LoadSessionRequest
  # @rbs host: Riffer::Rig::ACP::Host
  # @rbs return: Riffer::Rig::Runtime?
  def resumed(loader, request, host)
    runtime = loader.resume(
      request.session_id,
      extra_extensions: self.class.session_extensions(declarations(request.mcp_servers, host))
    )
    runtime && own(announcing_job_exits(runtime, host))
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: Riffer::Rig::Runtime
  def own(runtime)
    @lock.synchronize { @owned << runtime }
    runtime
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs host: Riffer::Rig::ACP::Host
  # @rbs return: Riffer::Rig::Runtime
  def announcing_job_exits(runtime, host)
    # A prompt in flight marks the exit on its own stream when it tells the
    # model. One starting meanwhile collects the exit from the inbox whose
    # lock this subscriber holds, so it cannot stream ahead of this update.
    runtime.on_job_exit do |completion|
      host.update(Riffer::Rig::ACP::Mapper.job_completion(completion)) unless runtime.busy?
    end
    runtime
  end

  # @rbs servers: Array[::ACP::Types::McpServer::t]
  # @rbs host: Riffer::Rig::ACP::Host
  # @rbs return: Hash[String, Riffer::Rig::Mcp::Declaration]
  def declarations(servers, host)
    Riffer::Rig::ACP::Servers.warnings(servers).each { |warning| host.notify(warning, level: :warning) }
    Riffer::Rig::ACP::Servers.declarations(servers)
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: Array[::ACP::Types::AvailableCommand]
  def available_commands(runtime)
    runtime.commands.map do |command|
      ::ACP::Types::AvailableCommand.new(name: command.name, description: command.description)
    end
  end
end
