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

    agent_input_r, @agent_input_w = IO.pipe
    @agent_output_r, @agent_output_w = IO.pipe
    env = Riffer::Rig::Env.new('MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test')
    build = lambda do |cwd, host, servers|
      @servers = servers
      runtime = Riffer::Rig::ACP.build_runtime(cwd, host, servers, env: env, home: @home)
      @built_runtimes << runtime
      runtime
    end
    @agent = Riffer::Rig::ACP.for(input: agent_input_r, output: @agent_output_w, env: env, home: @home, build: build)
    @agent_thread = Thread.new { @agent.run }
    @connection = ACP::ClientConnection.new(
      transport: ACP::Transport::Stdio.new(input: @agent_output_r, output: @agent_input_w),
      permission: lambda { |request|
        @permissions << request
        allow
      },
      updates: ->(notification) { @updates << notification }
    )
    @connection.start
    @connection.connect(ACP::Types::InitializeRequest.new(protocol_version: 1))
  end

  after do
    @agent_input_w.close unless @agent_input_w.closed?
    @agent_thread.join(5)
    @agent_output_w.close unless @agent_output_w.closed?
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def allow
    ACP::Types::RequestPermissionResponse.new(
      outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id: 'allow')
    )
  end

  def new_session(mcp_servers: [])
    @connection.session_new(ACP::Types::NewSessionRequest.new(cwd: @cwd, mcp_servers: mcp_servers))
  end

  def prompt_request(session_id, text)
    ACP::Types::PromptRequest.new(session_id: session_id, prompt: [ACP::Types::ContentBlock::Text.new(text: text)])
  end

  def prompt(session_id, text)
    updates = [] #: Array[ACP::Types::SessionUpdate::t]
    response = @connection.session_prompt(prompt_request(session_id, text)) { |update| updates << update }
    [response, updates]
  end

  def reply(content, tool_calls: [])
    @built_runtimes.last.agent.provider.stub_response(content, tool_calls: tool_calls)
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

  def message_texts
    @updates.filter_map do |notification|
      notification.update.content.text if notification.update.is_a?(ACP::Types::SessionUpdate::AgentMessageChunk)
    end
  end

  it 'returns the Runtime UUID as the sessionId' do
    session = new_session

    assert_equal @built_runtimes.last.id, session.session_id
  end

  it 'answers an unknown session with resource not found' do
    error = @connection.session_prompt(prompt_request('missing', 'hello'))

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

  it 'ends a completed turn with end_turn' do
    session = new_session
    reply('Hi from ACP.')
    response, = prompt(session.session_id, 'hello')

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

  it 'runs a tool call without asking the client for permission' do
    session = new_session
    File.write(File.join(@cwd, 'subject.txt'), 'contents')
    reply('Reading.', tool_calls: [{ name: 'read', arguments: { path: File.join(@cwd, 'subject.txt') } }])
    reply('All done.')
    prompt(session.session_id, 'read it')

    assert_empty @permissions
  end

  it 'ends a tool-call turn with end_turn' do
    session = new_session
    File.write(File.join(@cwd, 'subject.txt'), 'contents')
    reply('Reading.', tool_calls: [{ name: 'read', arguments: { path: File.join(@cwd, 'subject.txt') } }])
    reply('All done.')
    response, = prompt(session.session_id, 'read it')

    assert_equal 'end_turn', response.stop_reason
  end

  it 'ends a turn the client cancelled with cancelled' do
    session = new_session
    reply('Slow hello.')
    provider = @built_runtimes.last.agent.provider
    started = Queue.new
    provider.define_singleton_method(:build_request_params) do |messages, model, options|
      started << true
      sleep 0.5
      super(messages, model, options)
    end
    response = Thread.new do
      @connection.session_prompt(prompt_request(session.session_id, 'hello')) { |update| @updates << update }
    end
    started.pop
    @connection.session_cancel(ACP::Types::CancelNotification.new(session_id: session.session_id))

    assert_equal 'cancelled', response.value.stop_reason
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

    assert_equal %w[auth model skill:tidy reload], update.update.available_commands.map(&:name)
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

  it 'warns about a client-supplied non-stdio mcpServer' do
    new_session(
      mcp_servers: [{
        'name' => 'httpdocs', 'type' => 'http', 'url' => 'https://docs.example/mcp', 'headers' => []
      }]
    )
    wait_for { message_texts.any? { |text| text.include?('Skipped MCP server httpdocs') } }

    assert(message_texts.any? { |text| text.include?('only stdio servers are supported') })
  end

  describe 'namespace' do
    it 'references no Riffer::Rig constant outside the public host API' do
      sources = [File.expand_path('../../../lib/riffer/rig/acp.rb', __dir__),
                 *Dir[File.expand_path('../../../lib/riffer/rig/acp/**/*.rb', __dir__)]]
      referenced = sources.flat_map { |path| File.read(path).scan(/Riffer::Rig::(\w+)/).flatten }.uniq

      assert_empty referenced - %w[ACP Runtime Hosts Loader Events Extension Mcp Env VERSION]
    end
  end
end
