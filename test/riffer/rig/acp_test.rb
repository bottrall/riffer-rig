# frozen_string_literal: true

require 'test_helper'
require 'acp/sdk'

describe Riffer::Rig::ACP do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @updates = [] #: Array[ACP::Types::SessionNotification]
    @permissions = [] #: Array[ACP::Types::RequestPermissionRequest]
    @built_runtimes = [] #: Array[Riffer::Rig::Runtime]
    @servers = nil #: Hash[String, Riffer::Rig::Mcp::Declaration]?

    @served = [] #: Array[[IO, Thread, IO]]
    @env = Riffer::Rig::Env.new('MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test')
    @build = lambda do |cwd, host, servers|
      @servers = servers
      runtime = Riffer::Rig::ACP.build_runtime(cwd, host, servers, env: @env, home: @home)
      @built_runtimes << runtime
      runtime
    end
    @agent, @connection = serve(@env, build: @build)
  end

  after do
    hang_up
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def hang_up
    @served.each do |input, thread, output|
      input.close unless input.closed?
      thread.join(5)
      output.close unless output.closed?
    end
  end

  def reconnect(adopt:)
    hang_up
    @agent, @connection = serve(@env, build: @build, adopt: adopt)
  end

  def serve(env, build: nil, adopt: nil)
    agent_input_r, agent_input_w = IO.pipe
    agent_output_r, agent_output_w = IO.pipe
    agent = Riffer::Rig::ACP.for(
      input: agent_input_r, output: agent_output_w, env: env, home: @home, cwd: @cwd, build: build, adopt: adopt
    )
    @served << [agent_input_w, Thread.new { agent.run }, agent_output_w]
    connection = ACP::ClientConnection.new(
      transport: ACP::Transport::Stdio.new(input: agent_output_r, output: agent_input_w),
      permission: lambda { |request|
        @permissions << request
        allow
      },
      updates: ->(notification) { @updates << notification }
    )
    connection.start
    connection.connect(ACP::Types::InitializeRequest.new(protocol_version: 1))
    [agent, connection]
  end

  def invalid_env_connection
    serve(Riffer::Rig::Env::Invalid.new('RIFFER_MODEL: rejected')).last
  end

  def allow
    ACP::Types::RequestPermissionResponse.new(
      outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id: 'allow')
    )
  end

  def new_session(mcp_servers: [])
    @connection.new_session(ACP::Types::NewSessionRequest.new(cwd: @cwd, mcp_servers: mcp_servers))
  end

  def ready_session
    session = new_session
    wait_for do
      @updates.any? { |notification| notification.update.is_a?(ACP::Types::SessionUpdate::AvailableCommandsUpdate) }
    end
    session
  end

  def start_job(runtime, command)
    jobs = runtime.agent.context[:jobs] #: Riffer::Rig::Tools::Bash::Jobs
    jobs.register(Process.spawn(command, pgroup: true), command, File.open(File::NULL))
  end

  def ended_job(runtime)
    exits = Queue.new
    runtime.on_job_exit { |completion| exits << completion }
    start_job(runtime, 'true')
    exits.pop(timeout: 5)
  end

  def record_session_end(marker)
    FileUtils.mkdir_p(File.join(@home, '.riffer'))
    File.write(File.join(@home, '.riffer', 'rig.rb'), <<~RUBY)
      Riffer::Rig.extension('acp_close_probe') do |rig|
        rig.on(:session_end) { |event| File.write(#{marker.inspect}, event.reason.to_s) }
      end
    RUBY
  end

  def prompt_request(session_id, text)
    ACP::Types::PromptRequest.new(session_id: session_id, prompt: [ACP::Types::ContentBlock::Text.new(text: text)])
  end

  def prompt(session_id, text)
    updates = [] #: Array[ACP::Types::SessionUpdate::t]
    response = @connection.prompt_session(prompt_request(session_id, text)) { |update| updates << update }
    [response, updates]
  end

  def save_session(text)
    session = new_session
    reply('Reply.')
    prompt(session.session_id, text)
    session
  end

  def load(session_id, mcp_servers: [])
    updates = [] #: Array[ACP::Types::SessionUpdate::t]
    response = @connection.load_session(
      ACP::Types::LoadSessionRequest.new(cwd: @cwd, mcp_servers: mcp_servers, session_id: session_id)
    ) { |update| updates << update }
    [response, updates]
  end

  def adopt_session
    session = save_session('hello')
    reconnect(adopt: ->(id) { @built_runtimes.find { |runtime| runtime.id == id } })
    session
  end

  def prompts_seen_by(runtime)
    runtime.to_h[:messages].filter_map { |message| message[:content] if message[:role] == :user }
  end

  def tool_turn
    session = new_session
    File.write(File.join(@cwd, 'subject.txt'), 'contents')
    reply('Reading.', tool_calls: [{ name: 'read', arguments: { path: File.join(@cwd, 'subject.txt') } }])
    reply('All done.')
    prompt(session.session_id, 'hello')
    session
  end

  def reply(content, tool_calls: [])
    @built_runtimes.last.agent.provider.stub_response(content, tool_calls: tool_calls)
  end

  def hold_provider
    started = Queue.new
    gate = Queue.new
    @built_runtimes.last.agent.provider.define_singleton_method(:build_request_params) do |messages, model, options|
      started << true
      gate.pop
      super(messages, model, options)
    end
    [started, gate]
  end

  def wait_for(timeout: 5)
    deadline = Time.now + timeout
    until yield
      flunk('timed out waiting for the agent') if Time.now > deadline

      sleep 0.01
    end
  end

  def write_skill(name)
    dir = File.join(@cwd, '.agents', 'skills', name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'SKILL.md'), "---\nname: #{name}\ndescription: Skill #{name}.\n---\nDo #{name}.\n")
  end

  def write_project_rig
    FileUtils.mkdir_p(File.join(@cwd, '.riffer'))
    File.write(File.join(@cwd, '.riffer', 'rig.rb'), '')
  end

  def skipped_server_warning(name)
    wait_for { message_texts.any? { |text| text.include?("Skipped MCP server #{name}") } }
    message_texts.find { |text| text.include?("Skipped MCP server #{name}") }
  end

  def texts_of(updates)
    updates.filter_map do |update|
      update.content.text if update.is_a?(ACP::Types::SessionUpdate::AgentMessageChunk)
    end
  end

  def http_server(name)
    { 'name' => name, 'type' => 'http', 'url' => 'https://docs.example/mcp', 'headers' => [] }
  end

  def without_commands(updates)
    updates.grep_v(ACP::Types::SessionUpdate::AvailableCommandsUpdate)
  end

  def message_texts
    texts_of(@updates.map(&:update))
  end

  describe '.build_runtime' do
    it 'declares the client servers to the Runtime it builds' do
      notified = [] #: Array[String]
      host = Riffer::Rig::Hosts::Null.new
      host.define_singleton_method(:notify) { |message = nil, **| notified << message.to_s }
      declaration = Riffer::Rig::Mcp::Declaration.new(command: File.join(@cwd, 'mcp_stub.rb'))
      Riffer::Rig::ACP.build_runtime(@cwd, host, { 'acp-build-stub' => declaration }, env: @env, home: @home).close

      # riffer cannot register a stdio server yet, so the Runtime's refusal is
      # the only trace that the declaration reached it.
      assert(notified.any? { |message| message.include?('acp-build-stub') })
    end
  end

  describe '.session_extensions' do
    it 'builds no extension without servers' do
      assert_empty Riffer::Rig::ACP.session_extensions({})
    end

    it 'declares each server through rig.mcp' do
      declaration = Riffer::Rig::Mcp::Declaration.new(command: 'stub', args: ['--flag'], env: { 'TOKEN' => 't' })
      registrar = Riffer::Rig::ACP.session_extensions({ 'stub' => declaration }).first.trial({})

      assert_equal({ 'stub' => declaration }, registrar.mcp_servers)
    end
  end

  describe '#run' do
    it 'yields the connection once the client closes stdin' do
      input, client = IO.pipe
      client.close
      yielded = nil
      Riffer::Rig::ACP.for(input: input, output: StringIO.new, env: @env, home: @home, cwd: @cwd).run do |connection|
        yielded = connection
      end

      assert_instance_of ACP::AgentConnection, yielded
    end

    it 'returns 0 once the client closes stdin' do
      input, thread, = @served.first
      input.close

      assert_equal 0, thread.join(5)&.value
    end

    it 'closes a Runtime it built once the client disconnects' do
      marker = File.join(@home, 'session_end')
      record_session_end(marker)
      @agent, @connection = serve(@env)
      session = new_session
      prompt(session.session_id, 'hello')
      hang_up

      assert_equal 'close', File.read(marker)
    end

    it 'closes a Runtime it restored once the client disconnects' do
      marker = File.join(@home, 'session_end')
      session = save_session('hello')
      record_session_end(marker)
      load(session.session_id)
      prompt(session.session_id, 'again')
      hang_up

      assert_equal 'close', File.read(marker)
    end

    it 'leaves the Runtime its build hook returned running once the client disconnects' do
      new_session
      runtime = @built_runtimes.last
      start_job(runtime, 'sleep 30')
      hang_up
      running = runtime.running_job_count
      runtime.close

      assert_equal 1, running
    end
  end

  describe '#new_session' do
    it 'warns about a client-supplied non-stdio mcpServer' do
      new_session(
        mcp_servers: [{
          'name' => 'httpdocs', 'type' => 'http', 'url' => 'https://docs.example/mcp', 'headers' => []
        }]
      )
      wait_for { message_texts.any? { |text| text.include?('Skipped MCP server httpdocs') } }

      assert(message_texts.any? { |text| text.include?('only stdio servers are supported') })
    end

    it 'names a skipped sse mcpServer in the warning' do
      new_session(
        mcp_servers: [{ 'name' => 'ssedocs', 'type' => 'sse', 'url' => 'https://docs.example/sse', 'headers' => [] }]
      )

      assert_includes skipped_server_warning('ssedocs'), 'only stdio servers are supported'
    end

    it 'names a skipped mcpServer of an unknown type in the warning' do
      new_session(mcp_servers: [{ 'name' => 'odd', 'type' => 'websocket' }])

      assert_includes skipped_server_warning('odd'), 'only stdio servers are supported'
    end

    it 'turns client-supplied stdio mcpServers into rig.mcp declarations' do
      script = File.join(@cwd, 'mcp_stub.rb')
      File.write(script, '#!/usr/bin/env ruby')
      new_session(
        mcp_servers: [{
          'name' => 'stub', 'command' => script, 'args' => ['--flag'],
          'env' => [{ 'name' => 'TOKEN', 'value' => 't' }]
        }]
      )

      assert_equal(
        { 'stub' => Riffer::Rig::Mcp::Declaration.new(command: script, args: ['--flag'], env: { 'TOKEN' => 't' }) },
        @servers
      )
    end

    it 'sends the exit of a job that ends between prompts as an agent message chunk' do
      ready_session
      update = Riffer::Rig::ACP::Mapper.job_completion(ended_job(@built_runtimes.last))
      wait_for { message_texts.include?(update.content.text) }

      assert_includes message_texts, update.content.text
    end

    it 'sends nothing for a job that ends while a prompt is in flight' do
      session = ready_session
      runtime = @built_runtimes.last
      started, gate = hold_provider
      turn = Thread.new { prompt(session.session_id, 'hello') }
      started.pop
      ended_job(runtime)
      2.times { gate << true }
      texts = texts_of(turn.value.last) + message_texts

      refute(texts.any? { |text| text.include?('Background job') })
    end

    it 'returns the Runtime UUID as the sessionId' do
      session = new_session

      assert_equal @built_runtimes.last.id, session.session_id
    end

    it 'gives the session a host that relays its questions' do
      new_session
      wait_for { @updates.any? }

      assert_includes @built_runtimes.last.host.capabilities, :confirm
    end

    it 'answers a failed build with its message' do
      error = invalid_env_connection.new_session(ACP::Types::NewSessionRequest.new(cwd: @cwd, mcp_servers: []))

      assert_equal 'RIFFER_MODEL: rejected', error.message
    end
  end

  describe '#prompt' do
    it 'answers an unknown session with resource not found' do
      error = @connection.prompt_session(prompt_request('missing', 'hello'))

      assert_equal ACP::RequestError::RESOURCE_NOT_FOUND, error.code
    end

    it 'streams the turn as agent message chunks' do
      session = new_session
      reply('Hi from ACP.')
      _response, updates = prompt(session.session_id, 'hello')
      text = updates
             .filter_map do |update|
               update.content.text if update.is_a?(ACP::Types::SessionUpdate::AgentMessageChunk)
             end
             .join

      assert_includes text, 'Hi from ACP'
    end

    it 'runs a slash command instead of prompting the model' do
      session = ready_session
      prompt(session.session_id, '/cost')

      assert_empty prompts_seen_by(@built_runtimes.last)
    end

    it 'passes a slash command the text after its name' do
      session = ready_session
      prompt(session.session_id, '/model mock/other')

      assert_equal 'mock/other', @built_runtimes.last.model
    end

    it 'streams the output of a slash command as an agent message chunk' do
      session = ready_session
      _response, updates = prompt(session.session_id, '/cost')

      assert_equal [Riffer::Rig::Commands::Cost::NO_USAGE], texts_of(updates)
    end

    it 'streams the turn a slash command starts' do
      write_skill('tidy')
      session = ready_session
      reply('Tidied.')
      _response, updates = prompt(session.session_id, '/skill:tidy')

      assert_includes texts_of(updates).join, 'Tidied.'
    end

    it 'ends a completed turn with end_turn' do
      session = new_session
      reply('Hi from ACP.')
      response, = prompt(session.session_id, 'hello')

      assert_equal 'end_turn', response.stop_reason
    end

    it 'ends a slash command that runs no turn with end_turn' do
      session = ready_session
      response, = prompt(session.session_id, '/cost')

      assert_equal 'end_turn', response.stop_reason
    end

    it 'reports a tool call' do
      session = new_session
      File.write(File.join(@cwd, 'subject.txt'), 'contents')
      reply('Reading.', tool_calls: [{ name: 'read', arguments: { path: File.join(@cwd, 'subject.txt') } }])
      reply('All done.')
      _response, updates = prompt(session.session_id, 'read it')
      tool_call = updates.find { |update| update.is_a?(ACP::Types::SessionUpdate::ToolCall) }

      assert_equal 'read', tool_call&.name
    end

    it 'completes a tool call once it has run' do
      session = new_session
      File.write(File.join(@cwd, 'subject.txt'), 'contents')
      reply('Reading.', tool_calls: [{ name: 'read', arguments: { path: File.join(@cwd, 'subject.txt') } }])
      reply('All done.')
      _response, updates = prompt(session.session_id, 'read it')
      statuses = updates.filter_map do |update|
        [update.tool_call_id, update.status] if update.is_a?(ACP::Types::SessionUpdate::ToolCallUpdate)
      end

      assert_equal [%w[mock_call_0 completed]], statuses
    end

    it 'completes a tool call after reporting it' do
      session = new_session
      File.write(File.join(@cwd, 'subject.txt'), 'contents')
      reply('Reading.', tool_calls: [{ name: 'read', arguments: { path: File.join(@cwd, 'subject.txt') } }])
      reply('All done.')
      _response, updates = prompt(session.session_id, 'read it')
      tool_updates = updates.map { |update| update.class.name.to_s.split('::').last }.grep(/\AToolCall/)

      assert_equal %w[ToolCall ToolCallUpdate], tool_updates
    end

    it 'runs a tool call without asking the client for permission' do
      session = new_session
      File.write(File.join(@cwd, 'subject.txt'), 'contents')
      reply('Reading.', tool_calls: [{ name: 'read', arguments: { path: File.join(@cwd, 'subject.txt') } }])
      reply('All done.')
      prompt(session.session_id, 'read it')

      assert_empty @permissions
    end

    it 'breaks the agent message where a job exit is delivered' do
      session = ready_session
      update = Riffer::Rig::ACP::Mapper.job_completion(ended_job(@built_runtimes.last))
      wait_for { message_texts.include?(update.content.text) }
      reply('Hi from ACP.')
      _response, updates = prompt(session.session_id, 'hello')
      chunks = texts_of(updates)

      assert_equal Riffer::Rig::ACP::Mapper.job_exit.content.text, chunks.first
    end

    it 'ends a tool-call turn with end_turn' do
      session = new_session
      File.write(File.join(@cwd, 'subject.txt'), 'contents')
      reply('Reading.', tool_calls: [{ name: 'read', arguments: { path: File.join(@cwd, 'subject.txt') } }])
      reply('All done.')
      response, = prompt(session.session_id, 'read it')

      assert_equal 'end_turn', response.stop_reason
    end

    it 'answers a prompt on a busy session with the runtime error' do
      session = new_session
      reply('Slow hello.')
      started, gate = hold_provider
      first = Thread.new { prompt(session.session_id, 'hello') }
      started.pop
      # The client connection refuses a second stream on a session itself, so
      # only a direct call reaches the Runtime's own refusal.
      error = @agent.prompt(prompt_request(session.session_id, 'again'))
      gate << true
      first.join

      assert_includes error.message, 'already running'
    end

    it 'answers a prompt on a closed session with the runtime error' do
      session = new_session
      @built_runtimes.last.close
      error = @connection.prompt_session(prompt_request(session.session_id, 'hello'))

      assert_includes error.message, 'closed'
    end
  end

  describe '#load_session' do
    it 'answers an unknown session id with resource not found' do
      error = @connection.load_session(
        ACP::Types::LoadSessionRequest.new(cwd: @cwd, mcp_servers: [], session_id: 'missing')
      )

      assert_equal ACP::RequestError::RESOURCE_NOT_FOUND, error.code
    end

    it 'replays the stored messages of an adopted session' do
      session = adopt_session
      _response, updates = load(session.session_id)

      assert_equal(%w[hello Reply.], without_commands(updates).map { |update| update.content.text })
    end

    it 'sends the commands of an adopted session after its replay' do
      write_skill('tidy')
      session = adopt_session
      _response, updates = load(session.session_id)

      assert_equal %w[auth model cost skill:tidy reload trace], updates.last.available_commands.map(&:name)
    end

    it 'runs a prompt from a later connection on the adopted runtime' do
      session = adopt_session
      load(session.session_id)
      reply('Again.')
      prompt(session.session_id, 'again')

      assert_equal %w[hello again], prompts_seen_by(@built_runtimes.last)
    end

    it 'reaches the adopted runtime with a cancel from a later connection' do
      session = adopt_session
      cancelled = Queue.new
      @built_runtimes.last.define_singleton_method(:cancel) do
        cancelled << true
        super()
      end
      load(session.session_id)
      @connection.cancel_session(ACP::Types::CancelNotification.new(session_id: session.session_id))

      assert cancelled.pop(timeout: 5)
    end

    it 'sends the notifies of an adopted runtime to the later connection' do
      session = adopt_session
      @updates.clear
      load(session.session_id)
      @built_runtimes.last.host.notify('still here')
      wait_for { message_texts.include?('still here') }

      assert_includes message_texts, 'still here'
    end

    it 'sends the job exits of an adopted runtime to the later connection' do
      session = adopt_session
      load(session.session_id)
      @updates.clear
      update = Riffer::Rig::ACP::Mapper.job_completion(ended_job(@built_runtimes.last))
      wait_for { message_texts.include?(update.content.text) }

      assert_includes message_texts, update.content.text
    end

    it 'adopts a runtime whose host is not an ACP host' do
      session = save_session('hello')
      runtime = Riffer::Rig::ACP.build_runtime(@cwd, Riffer::Rig::Hosts::Null.new, {}, env: @env, home: @home)
      reconnect(adopt: ->(_id) { runtime })
      load(session.session_id)
      runtime.agent.provider.stub_response('Again.')
      prompt(session.session_id, 'again')
      runtime.close

      assert_equal %w[again], prompts_seen_by(runtime)
    end

    it 'declares no client mcpServer on an adopted runtime' do
      session = adopt_session
      _response, updates = load(session.session_id, mcp_servers: [http_server('httpdocs')])

      assert_empty(texts_of(updates).grep(/Skipped MCP server/))
    end

    it 'restores from the store when the hook declines the session' do
      session = save_session('hello')
      reconnect(adopt: ->(_id) {})
      load(session.session_id)
      reply('Again.')
      prompt(session.session_id, 'again')

      assert_equal %w[hello], prompts_seen_by(@built_runtimes.first)
    end

    it 'sends the client no permission request while a loaded session builds' do
      session = save_session('first prompt')
      write_project_rig
      load(session.session_id)

      assert_empty @permissions
    end

    it 'sends a build-time notify as an update for the loaded session' do
      session = save_session('first prompt')
      FileUtils.mkdir_p(File.join(@home, '.riffer'))
      File.write(File.join(@home, '.riffer', 'rig.rb'), "raise 'broken rig'\n")
      _response, updates = load(session.session_id)

      assert(texts_of(updates).any? { |text| text.include?('broken rig') })
    end

    it 'warns about a client-supplied non-stdio mcpServer of a loaded session' do
      session = save_session('first prompt')
      _response, updates = load(session.session_id, mcp_servers: [http_server('httpdocs')])

      assert_includes texts_of(updates), 'Skipped MCP server httpdocs: only stdio servers are supported'
    end

    it 'declares the client stdio mcpServers to the Runtime it restores' do
      session = save_session('first prompt')
      stub = { 'name' => 'acp-load-stub', 'command' => File.join(@cwd, 'mcp_stub.rb'), 'args' => [], 'env' => [] }
      _response, updates = load(session.session_id, mcp_servers: [stub])

      # riffer cannot register a stdio server yet, so the Runtime's refusal is
      # the only trace that the declaration reached it.
      assert(texts_of(updates).any? { |text| text.include?('acp-load-stub runs over stdio') })
    end

    it 'replays the stored messages of a loaded session in order' do
      session = tool_turn

      _response, updates = load(session.session_id)

      replay = without_commands(updates).map do |update|
        text = update.is_a?(ACP::Types::SessionUpdate::ToolCall) ? update.name : update.content.text
        [update.class.name.split('::').last, text]
      end

      assert_equal(
        [['UserMessageChunk', 'hello'], ['AgentMessageChunk', 'Reading.'],
         ['ToolCall', 'read'], ['AgentMessageChunk', 'All done.']],
        replay
      )
    end

    it 'sends the commands of a restored session after its replay' do
      write_skill('tidy')
      session = save_session('first prompt')
      _response, updates = load(session.session_id)

      assert_equal %w[auth model cost skill:tidy reload trace], updates.last.available_commands.map(&:name)
    end

    it 'continues the conversation after a load' do
      session = tool_turn
      load(session.session_id)
      prompt(session.session_id, 'again')

      assert_equal 2, @built_runtimes.last.agent.provider.calls.size
    end

    it 'relays a question of the loaded session to the client' do
      session = save_session('first prompt')
      load(session.session_id)
      write_project_rig
      prompt(session.session_id, 'again')

      assert_equal [session.session_id], @permissions.map(&:session_id)
    end

    it 'answers a failed load with its message' do
      error = invalid_env_connection.load_session(
        ACP::Types::LoadSessionRequest.new(cwd: @cwd, mcp_servers: [], session_id: 'any')
      )

      assert_equal 'RIFFER_MODEL: rejected', error.message
    end
  end

  describe '#list_sessions' do
    it 'lists the saved sessions of the cwd' do
      first = save_session('first prompt')
      second = save_session('second prompt')

      response = @connection.list_sessions(ACP::Types::ListSessionsRequest.new(cwd: @cwd))

      assert_equal [first.session_id, second.session_id].sort, response.sessions.map(&:session_id).sort
    end

    it 'titles a listed session with its first prompt' do
      session = save_session("first prompt\nsecond line")

      response = @connection.list_sessions(ACP::Types::ListSessionsRequest.new(cwd: @cwd))
      listed = response.sessions.find { |info| info.session_id == session.session_id }

      assert_equal 'first prompt', listed&.title
    end

    it 'stamps a listed session with its last update' do
      session = save_session('first prompt')

      response = @connection.list_sessions(ACP::Types::ListSessionsRequest.new(cwd: @cwd))
      listed = response.sessions.find { |info| info.session_id == session.session_id }

      assert(Time.iso8601(listed&.updated_at.to_s))
    end

    it 'lists the saved sessions of every cwd when the request names none' do
      session = save_session('first prompt')

      response = @connection.list_sessions(ACP::Types::ListSessionsRequest.new)

      assert_includes response.sessions.map(&:session_id), session.session_id
    end

    it 'answers a failed listing with its message' do
      error = invalid_env_connection.list_sessions(ACP::Types::ListSessionsRequest.new(cwd: @cwd))

      assert_equal 'RIFFER_MODEL: rejected', error.message
    end
  end

  describe '#cancel' do
    it 'ignores a cancel for an unknown session' do
      assert_nil @agent.cancel(ACP::Types::CancelNotification.new(session_id: 'missing'))
    end

    it 'ends a turn the client cancelled with cancelled' do
      session = new_session
      reply('Slow hello.')
      started, gate = hold_provider
      response = Thread.new do
        @connection.prompt_session(prompt_request(session.session_id, 'hello')) { |update| @updates << update }
      end
      started.pop
      @connection.cancel_session(ACP::Types::CancelNotification.new(session_id: session.session_id))
      # The agent handles notifications in arrival order on its reader thread,
      # so this reply proves the cancel landed before the provider resumes.
      @connection.prompt_session(prompt_request('missing', 'flush'))
      gate << true

      assert_equal 'cancelled', response.value.stop_reason
    end
  end

  describe '#session_created' do
    it 'sends nothing for a session it never created' do
      assert_nil @agent.session_created(ACP::Types::NewSessionResponse.new(session_id: 'missing'))
    end

    it 'sends the runtime commands as available_commands_update' do
      write_skill('tidy')
      new_session
      wait_for do
        @updates.any? do |notification|
          notification.update.is_a?(ACP::Types::SessionUpdate::AvailableCommandsUpdate)
        end
      end
      update = @updates.find do |notification|
        notification.update.is_a?(ACP::Types::SessionUpdate::AvailableCommandsUpdate)
      end

      assert_equal %w[auth model cost skill:tidy reload trace], update.update.available_commands.map(&:name)
    end
  end

  describe 'namespace' do
    it 'references no Riffer::Rig constant outside the public host API' do
      sources = [File.expand_path('../../../lib/riffer/rig/acp.rb', __dir__),
                 *Dir[File.expand_path('../../../lib/riffer/rig/acp/**/*.rb', __dir__)]]
      referenced = sources.flat_map { |path| File.read(path).scan(/Riffer::Rig::(\w+)/).flatten }.uniq

      assert_empty referenced - %w[ACP Runtime Hosts Loader Events Extension Mcp Env Command VERSION]
    end
  end
end
