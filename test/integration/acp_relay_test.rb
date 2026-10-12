# frozen_string_literal: true

require 'test_helper'
require 'acp/sdk'

describe 'relaying host questions to an ACP client' do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @permissions = [] #: Array[ACP::Types::RequestPermissionRequest]
    @runtimes = [] #: Array[Riffer::Rig::Runtime]
    env = Riffer::Rig::Env.new('MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test')
    build = lambda do |cwd, host, servers|
      Riffer::Rig::ACP.build_runtime(cwd, host, servers, env: env, home: @home).tap { |runtime| @runtimes << runtime }
    end
    agent_input_r, @agent_input_w = IO.pipe
    agent_output_r, @agent_output_w = IO.pipe
    agent = Riffer::Rig::ACP.for(
      input: agent_input_r, output: @agent_output_w, env: env, home: @home, build: build, relay: true
    )
    @agent_thread = Thread.new { agent.run }
    @connection = ACP::ClientConnection.new(
      transport: ACP::Transport::Stdio.new(input: agent_output_r, output: @agent_input_w),
      permission: lambda { |request|
        @permissions << request
        select_first(request)
      },
      elicitation: ->(_request) { accept('typed') }
    )
    @connection.start
    @connection.connect(ACP::Types::InitializeRequest.new(protocol_version: 1, client_capabilities: form_elicitation))
  end

  after do
    @agent_input_w.close unless @agent_input_w.closed?
    @agent_thread.join(5)
    @agent_output_w.close unless @agent_output_w.closed?
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def form_elicitation
    ACP::Types::ClientCapabilities.new(
      elicitation: ACP::Types::ElicitationCapabilities.new(form: ACP::Types::ElicitationFormCapabilities.new)
    )
  end

  def select_first(request)
    ACP::Types::RequestPermissionResponse.new(
      outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id: request.options.first.option_id)
    )
  end

  def accept(answer)
    ACP::Types::CreateElicitationResponse.new(
      action: ACP::Types::CreateElicitationResponse::Action::Accept.new(content: { 'answer' => answer })
    )
  end

  def relaying_host
    session = @connection.new_session(ACP::Types::NewSessionRequest.new(cwd: @cwd, mcp_servers: []))
    host = @runtimes.last.host
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    sleep 0.01 until host.capabilities.include?(:confirm) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    [session, host]
  end

  it 'confirms with the option the client selected' do
    _, host = relaying_host

    assert host.confirm('Proceed?')
  end

  it 'asks permission on the session the host belongs to' do
    session, host = relaying_host
    host.confirm('Proceed?')

    assert_equal session.session_id, @permissions.last.session_id
  end

  it 'titles the permission request with the question' do
    _, host = relaying_host
    host.confirm('Proceed?')

    assert_equal 'Proceed?', @permissions.last.tool_call.title
  end

  it 'answers an ask with options with the option the client selected' do
    _, host = relaying_host

    assert_equal 'red', host.ask('Colour?', options: %w[red blue])
  end

  it 'answers a free-text ask with what the client typed into the elicitation' do
    _, host = relaying_host

    assert_equal 'typed', host.ask('Name?')
  end
end
