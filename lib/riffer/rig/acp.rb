# frozen_string_literal: true

require 'acp/sdk'
require 'time'

# The ACP tier: Runtime events reach the client only through this adapter's
# mapping, so nothing else in rig may translate an event into an ACP type.
class Riffer::Rig::ACP
  AGENT_NAME = 'riffer' #: String
  AGENT_TITLE = 'Riffer' #: String

  SESSION_EXTENSION = 'acp' #: String

  TOOL_KINDS = {
    'read' => ::ACP::Types::ToolKind::READ,
    'write' => ::ACP::Types::ToolKind::EDIT,
    'edit' => ::ACP::Types::ToolKind::EDIT,
    'bash' => ::ACP::Types::ToolKind::EXECUTE
  }.freeze #: Hash[String, String]

  # @rbs @input: IO
  # @rbs @output: IO
  # @rbs @env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs @home: String
  # @rbs @build: ^(String, Riffer::Rig::Hosts::_Host, Hash[String, Riffer::Rig::Mcp::Declaration]) -> Riffer::Rig::Runtime
  # @rbs @client: ::ACP::AgentConnection::_Client?
  # @rbs @sessions: Hash[String, Riffer::Rig::Runtime]
  # @rbs @hosts: Hash[String, Riffer::Rig::ACP::Host]
  # @rbs @lock: Thread::Mutex

  # @rbs input: IO
  # @rbs output: IO
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs build: (^(String, Riffer::Rig::Hosts::_Host, Hash[String, Riffer::Rig::Mcp::Declaration]) -> Riffer::Rig::Runtime)?
  # @rbs return: Riffer::Rig::ACP
  def self.for(input:, output:, env:, home:, build: nil)
    new(input: input, output: output, env: env, home: home, build: build)
  end

  # Builds the Runtime a session runs on: the client's MCP servers flow
  # through the rig.mcp seam as a synthetic extension, so a reload rebuild
  # re-declares them and a same-name declaration from an extension replaces
  # them with the usual notify.
  # @rbs cwd: String
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs servers: Hash[String, Riffer::Rig::Mcp::Declaration]
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs return: Riffer::Rig::Runtime
  def self.build_runtime(cwd, host, servers, env:, home:)
    extension = session_extension(servers)
    Riffer::Rig::Loader.runtime(
      cwd: cwd, host: host, env: env, home: home, extra_extensions: extension ? [extension] : []
    )
  end

  # @rbs servers: Hash[String, Riffer::Rig::Mcp::Declaration]
  # @rbs return: Riffer::Rig::Extension?
  def self.session_extension(servers)
    return nil if servers.empty?

    Riffer::Rig::Extension.new(SESSION_EXTENSION) do |rig|
      servers.each { |name, server| rig.mcp(name, command: server.command, args: server.args, env: server.env) }
    end
  end

  # @rbs input: IO
  # @rbs output: IO
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs build: (^(String, Riffer::Rig::Hosts::_Host, Hash[String, Riffer::Rig::Mcp::Declaration]) -> Riffer::Rig::Runtime)?
  # @rbs return: void
  def initialize(input:, output:, env:, home:, build: nil)
    @input = input
    @output = output
    @env = env
    @home = home
    @build = build || ->(cwd, host, servers) { self.class.build_runtime(cwd, host, servers, env: @env, home: @home) }
    @client = nil
    @sessions = {}
    @hosts = {}
    @lock = Mutex.new
  end

  # Serves the connection until the client closes stdin; then the reader
  # thread ends and run returns.
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
    0
  end

  # @rbs request: ::ACP::Types::NewSessionRequest
  # @rbs return: (::ACP::Types::NewSessionResponse | ::ACP::RequestError)
  def new_session(request)
    host = Riffer::Rig::ACP::Host.new(client: client)
    servers = declarations(request.mcp_servers, host)
    runtime = @build.call(request.cwd, host, servers)
    @lock.synchronize do
      @sessions[runtime.id] = runtime
      @hosts[runtime.id] = host
    end
    ::ACP::Types::NewSessionResponse.new(session_id: runtime.id)
  rescue StandardError => e
    ::ACP::RequestError.new(code: ::ACP::RequestError::INTERNAL_ERROR, message: e.message)
  end

  # @rbs request: ::ACP::Types::PromptRequest
  # @rbs return: (::ACP::Types::PromptResponse | ::ACP::RequestError)
  def prompt(request)
    runtime = session(request.session_id)
    return ::ACP::RequestError.resource_not_found unless runtime

    # @type var stop_reason: Symbol?
    stop_reason = nil
    runtime.prompt(prompt_text(request.prompt)) do |event|
      case event
      when Riffer::StreamEvents::TextDelta
        client.update(request.session_id, message_chunk(event.content))
      when Riffer::StreamEvents::ToolCallDone
        client.update(request.session_id, tool_call(event))
      when Riffer::Rig::Events::TurnEnd
        stop_reason = event.stop_reason
      end
    end
    ::ACP::Types::PromptResponse.new(stop_reason: stop_reason_of(stop_reason))
  rescue Riffer::Rig::Runtime::BusyError, Riffer::Rig::Runtime::ClosedError => e
    ::ACP::RequestError.new(code: ::ACP::RequestError::INTERNAL_ERROR, message: e.message)
  end

  # Restores a saved session: a Loader at the request's cwd reads the entries
  # and rebuilds the Runtime, the stored messages replay as updates, then the
  # request answers and a following prompt continues the conversation. The
  # host takes the session id before the build so a build-time notify still
  # reaches the client as an update for this session.
  # @rbs request: ::ACP::Types::LoadSessionRequest
  # @rbs return: (::ACP::Types::LoadSessionResponse | ::ACP::RequestError)
  def load_session(request)
    host = Riffer::Rig::ACP::Host.new(client: client)
    host.session_id = request.session_id
    loader = Riffer::Rig::Loader.new(cwd: request.cwd, host: host, env: @env, home: @home)
    runtime = loader.resume(request.session_id)
    return ::ACP::RequestError.resource_not_found unless runtime

    @lock.synchronize do
      @sessions[request.session_id] = runtime
      @hosts[request.session_id] = host
    end
    loader.messages(request.session_id)
          .filter_map { |message| replay_of(message) }
          .each { |update| client.update(request.session_id, update) }
    ::ACP::Types::LoadSessionResponse.new
  rescue StandardError => e
    ::ACP::RequestError.new(code: ::ACP::RequestError::INTERNAL_ERROR, message: e.message)
  end

  # @rbs request: ::ACP::Types::ListSessionsRequest
  # @rbs return: (::ACP::Types::ListSessionsResponse | ::ACP::RequestError)
  def list_sessions(request)
    loader = Riffer::Rig::Loader.new(
      cwd: request.cwd || Dir.pwd,
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
    ::ACP::RequestError.new(code: ::ACP::RequestError::INTERNAL_ERROR, message: e.message)
  end

  # Runs on the transport's reader thread, so it only sets the cancel flag.
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

  # @rbs return: ::ACP::AgentConnection::_Client
  def client
    @client or raise 'ACP agent used before ::ACP::AgentConnection.start built it'
  end

  # @rbs id: String
  # @rbs return: Riffer::Rig::Runtime?
  def session(id)
    @lock.synchronize { @sessions[id] }
  end

  # @rbs servers: Array[::ACP::Types::McpServer::t]
  # @rbs host: Riffer::Rig::ACP::Host
  # @rbs return: Hash[String, Riffer::Rig::Mcp::Declaration]
  def declarations(servers, host)
    servers.filter_map { |server| declaration_of(server, host) }.to_h
  end

  # @rbs server: ::ACP::Types::McpServer::t
  # @rbs host: Riffer::Rig::ACP::Host
  # @rbs return: [String, Riffer::Rig::Mcp::Declaration]?
  def declaration_of(server, host)
    unless server.is_a?(::ACP::Types::McpServerStdio)
      host.notify("Skipped MCP server #{server_name(server)}: only stdio servers are supported", level: :warning)
      return nil
    end

    [
      server.name,
      Riffer::Rig::Mcp::Declaration.new(command: server.command, args: server.args, env: stdio_env(server))
    ]
  end

  # @rbs server: ::ACP::Types::McpServer::t
  # @rbs return: String
  def server_name(server)
    case server
    when ::ACP::Types::McpServer::Http, ::ACP::Types::McpServer::Sse then server.name
    when Hash then server['name'].to_s
    else 'unnamed'
    end
  end

  # @rbs server: ::ACP::Types::McpServerStdio
  # @rbs return: Hash[String, String]
  def stdio_env(server)
    server.env.to_h { |variable| [variable.name, variable.value] }
  end

  # Text and resource links are ACP's must-support prompt blocks; the client
  # cannot send the others unless the agent advertised them.
  # @rbs blocks: Array[::ACP::Types::ContentBlock::t]
  # @rbs return: String
  def prompt_text(blocks)
    blocks.filter_map { |block| prompt_text_of(block) }.join("\n\n")
  end

  # @rbs block: ::ACP::Types::ContentBlock::t
  # @rbs return: String?
  def prompt_text_of(block)
    case block
    when ::ACP::Types::ContentBlock::Text then block.text
    when ::ACP::Types::ContentBlock::ResourceLink then "#{block.title || block.name} #{block.uri}"
    end
  end

  # @rbs content: String
  # @rbs return: ::ACP::Types::SessionUpdate::AgentMessageChunk
  def message_chunk(content)
    ::ACP::Types::SessionUpdate::AgentMessageChunk.new(content: text_block(content))
  end

  # @rbs text: String
  # @rbs return: ::ACP::Types::ContentBlock::Text
  def text_block(text)
    ::ACP::Types::ContentBlock::Text.new(text: text)
  end

  # A stored message replays as the update it was when it first streamed.
  # @rbs message: Hash[Symbol, untyped]
  # @rbs return: ::ACP::Types::SessionUpdate::t?
  def replay_of(message)
    case message[:role]
    when 'user' then ::ACP::Types::SessionUpdate::UserMessageChunk.new(content: text_block(message[:content].to_s))
    when 'assistant' then message_chunk(message[:content].to_s)
    when 'tool' then replayed_tool_call(message)
    end
  end

  # The stored result is all a replayed call has: the arguments live in the
  # assistant message's tool_calls, so the title is the name alone.
  # @rbs message: Hash[Symbol, untyped]
  # @rbs return: ::ACP::Types::SessionUpdate::ToolCall
  def replayed_tool_call(message)
    name = message[:name].to_s
    ::ACP::Types::SessionUpdate::ToolCall.new(
      tool_call_id: message[:tool_call_id].to_s,
      title: name,
      name: name,
      kind: TOOL_KINDS.fetch(name, ::ACP::Types::ToolKind::OTHER),
      status: ::ACP::Types::ToolCallStatus::COMPLETED,
      content: [::ACP::Types::ToolCallContent::Content.new(content: text_block(message[:content].to_s))]
    )
  end

  # riffer's stream has no completion boundary for a tool call, so a call goes
  # out once, in progress, when its arguments are complete.
  # @rbs event: Riffer::StreamEvents::ToolCallDone
  # @rbs return: ::ACP::Types::SessionUpdate::ToolCall
  def tool_call(event)
    ::ACP::Types::SessionUpdate::ToolCall.new(
      tool_call_id: event.call_id,
      title: "#{event.name}(#{event.arguments})",
      name: event.name,
      kind: TOOL_KINDS.fetch(event.name, ::ACP::Types::ToolKind::OTHER),
      status: ::ACP::Types::ToolCallStatus::IN_PROGRESS
    )
  end

  # riffer's failure reasons (:error, :other, :guardrail_blocked) have no ACP
  # counterpart; refusal is the closest signal that the turn did not complete.
  # @rbs stop_reason: Symbol?
  # @rbs return: String
  def stop_reason_of(stop_reason)
    case stop_reason
    when :completed then ::ACP::Types::StopReason::END_TURN
    when Riffer::Rig::Runtime::INTERRUPT_CANCELLED then ::ACP::Types::StopReason::CANCELLED
    when :max_steps then ::ACP::Types::StopReason::MAX_TURN_REQUESTS
    when :context_window, :length, :content_filter, :malformed_output then ::ACP::Types::StopReason::MAX_TOKENS
    else ::ACP::Types::StopReason::REFUSAL
    end
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: Array[::ACP::Types::AvailableCommand]
  def available_commands(runtime)
    runtime.commands.map do |command|
      ::ACP::Types::AvailableCommand.new(name: command.name, description: command.description)
    end
  end
end
