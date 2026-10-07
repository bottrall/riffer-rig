# frozen_string_literal: true

require 'test_helper'
require_relative '../../fixtures/mcp_https_server'

describe Riffer::Rig::Runtime do
  before do
    @extension = Riffer::Rig.extension('test_runtime_tools') do |rig|
      rig.tool Riffer::Rig::Tools::Read
      rig.tool Riffer::Rig::Tools::Write
      rig.tool Riffer::Rig::Tools::Edit
      rig.tool Riffer::Rig::Tools::Bash
    end
  end

  after do
    Riffer::Rig.instance_variable_get(:@extensions).delete('test_runtime_tools')
  end

  it 'prompts with a block, yielding riffer stream events' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')
    events = []
    runtime.prompt('hello') { |event| events << event }

    assert(events.any?(Riffer::StreamEvents::TextDone))
  end

  it 'prompts without a block, returning an enumerator' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    assert_instance_of Enumerator, runtime.prompt('hello')
  end

  it 'asks and returns riffer response with the content' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    response = runtime.ask('hello')

    assert_equal 'All done.', response.content
  end

  it 'asks and reports how the run ended' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    response = runtime.ask('hello')

    assert_equal :completed, response.outcome.reason
  end

  it 'asks and carries the run token usage' do
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.', token_usage: usage)

    response = runtime.ask('hello')

    assert_equal usage, response.token_usage
  end

  it 'asks and lists the tool calls the model made' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read])
    runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
    runtime.agent.provider.stub_response('The file says hi.')

    response = runtime.ask('read /tmp/x')

    names = response.messages.filter_map do |message|
      next unless message.is_a?(Riffer::Messages::Assistant)

      message.tool_calls.map(&:name)
    end.flatten

    assert_equal ['read'], names
  end

  it 'ends a capped run with the max_steps outcome' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read], max_steps: 1)
    runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
    runtime.agent.provider.stub_response('second response')

    response = runtime.ask('go')

    assert_equal :max_steps, response.outcome.reason
  end

  it 'hands its model options to the agent' do
    runtime = Riffer::Rig::Runtime.new('mock/test', model_options: { reasoning: 'high' })

    assert_equal({ reasoning: 'high' }, runtime.agent.config.model_options)
  end

  it 'sends its model options with each request' do
    runtime = Riffer::Rig::Runtime.new('mock/test', model_options: { reasoning: 'high' })
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_equal 'high', runtime.agent.provider.calls.last[:reasoning]
  end

  it 'keeps its model options through a rebuild' do
    runtime = Riffer::Rig::Runtime.new('mock/test', model_options: { reasoning: 'high' })
    runtime.rebuild(extensions: [], settings: {})

    assert_equal({ reasoning: 'high' }, runtime.agent.config.model_options)
  end

  it 're-derives its model options for the new provider on a switch' do
    runtime = Riffer::Rig::Runtime.new(
      'mock/test', model_options: { reasoning: 'high' }, settings: { reasoning: 'high' }
    )
    runtime.model = 'gemini/gem-2.5-pro'

    assert_equal({}, runtime.agent.config.model_options)
  end

  it 'enables the provider option of a native tool the provider supports' do
    runtime = Riffer::Rig::Runtime.new('mock/test', native_tools: { web_search: true })

    assert_equal({ web_search: true }, runtime.agent.config.model_options)
  end

  it 'passes a switch object through as the option value' do
    runtime = Riffer::Rig::Runtime.new('mock/test', native_tools: { web_search: { max_uses: 3 } })

    assert_equal({ web_search: { max_uses: 3 } }, runtime.agent.config.model_options)
  end

  it 'carries the provider option on the request' do
    runtime = Riffer::Rig::Runtime.new('mock/test', native_tools: { web_search: true })
    runtime.agent.provider.stub_response('All done.')
    events = []
    runtime.prompt('search') { |event| events << event }

    assert(events.any?(Riffer::StreamEvents::WebSearchDone))
  end

  it 'drops the switch of a native tool the provider does not support' do
    runtime = Riffer::Rig::Runtime.new('gemini/gem-2.5-pro', native_tools: { web_search: true })

    assert_equal({}, runtime.agent.config.model_options)
  end

  it 'adds no provider options without a switch' do
    runtime = Riffer::Rig::Runtime.new('mock/test')

    assert_equal({}, runtime.agent.config.model_options)
  end

  it 're-derives the provider option for the new provider on a switch' do
    runtime = Riffer::Rig::Runtime.new('mock/test', native_tools: { web_search: true })
    runtime.model = 'gemini/gem-2.5-pro'

    assert_equal({}, runtime.agent.config.model_options)
  end

  it 'refuses an ask while a prompt is running' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('first')
    runtime.agent.provider.stub_response('second')

    assert_raises(Riffer::Rig::Runtime::BusyError) do
      runtime.prompt('hello') do
        runtime.ask('second')
      end
    end
  end

  it 'keeps ask and prompt from colliding' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    assert_nil runtime.prompt('hello') { |event| event }
  end

  it 'registers the bundled tool classes through an extension' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Write, Riffer::Rig::Tools::Edit, Riffer::Rig::Tools::Bash],
                 runtime.agent.tools
  end

  it 'gives a second runtime its own tools' do
    other = Riffer::Rig.extension('test_runtime_other') { |rig| rig.tool Riffer::Rig::Tools::Read }
    Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    two = Riffer::Rig::Runtime.new('mock/test', extensions: [other])

    assert_equal [Riffer::Rig::Tools::Read], two.agent.tools
  end

  it 'keeps the process registry shared between runtimes' do
    other = Riffer::Rig.extension('test_runtime_other') { |rig| rig.tool Riffer::Rig::Tools::Read }
    one = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    Riffer::Rig::Runtime.new('mock/test', extensions: [other])

    assert_equal 4, one.agent.tools.length
  end

  it 'filters the registered tools by the allowlist' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read bash])

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Bash], runtime.agent.tools
  end

  it 'stores credentials as given' do
    credentials = { anthropic: { api_key: 'sk-ant-test' } }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], credentials: credentials)

    assert_same credentials, runtime.credentials
  end

  it 'defaults to no credentials' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    assert_empty runtime.credentials
  end

  it 'accepts keywords whose tickets have not landed' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], snapshot: nil)

    assert_instance_of Riffer::Rig::Runtime, runtime
  end

  it 'defaults to an unlimited agent loop' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    assert_nil runtime.agent.config.max_steps
  end

  it 'forwards max_steps to the agent' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], max_steps: 3)

    assert_equal 3, runtime.agent.config.max_steps
  end

  it 'names the agent in the base prompt' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    assert_includes runtime.agent.instruction_message.content, 'You are riffer, a general-purpose agent.'
  end

  it 'states the norms in the base prompt' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    assert_includes runtime.agent.instruction_message.content, 'Be concise. Lead with the outcome'
  end

  it 'carries the date and cwd in the environment block' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], cwd: '/tmp/proj')

    assert_includes runtime.agent.instruction_message.content,
                    "Current date: #{Date.today}\nCurrent working directory: /tmp/proj"
  end

  it 'lists no tools in the base prompt' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    refute_includes runtime.agent.instruction_message.content, 'read:'
  end

  it 'swaps the name inside the base prompt' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], name: 'sidekick')

    assert_includes runtime.agent.instruction_message.content, 'You are sidekick, a general-purpose agent.'
  end

  it 'replaces the base prompt with instructions' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], instructions: 'CUSTOM_BASE')

    assert_includes runtime.agent.instruction_message.content, 'CUSTOM_BASE'
  end

  it 'keeps the environment block under custom instructions' do
    runtime = Riffer::Rig::Runtime.new(
      'mock/test',
      extensions: [@extension],
      instructions: 'CUSTOM_BASE',
      cwd: '/tmp/proj'
    )

    assert_includes runtime.agent.instruction_message.content,
                    "Current date: #{Date.today}\nCurrent working directory: /tmp/proj"
  end

  it 'drops the default base under custom instructions' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], instructions: 'CUSTOM_BASE')

    refute_includes runtime.agent.instruction_message.content, 'general-purpose agent'
  end

  it 'renders sections in load order between the base and the environment block' do
    sections = Riffer::Rig::Extension.new('sections') do |rig|
      rig.prompt(:first) { 'SECTION_ONE' }
      rig.prompt(:second) { 'SECTION_TWO' }
    end
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [sections], cwd: '/tmp/proj')
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_match(
      /Lead with the outcome.*\n\nSECTION_ONE\n\nSECTION_TWO\n\nCurrent date: /m,
      runtime.agent.provider.calls.last[:messages].first[:content]
    )
  end

  it 're-evaluates a section every turn without a rebuild' do
    branch = 'main'
    sections = Riffer::Rig::Extension.new('sections') { |rig| rig.prompt(:branch) { "Branch: #{branch}" } }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [sections])
    runtime.agent.provider.stub_response('One.')
    runtime.agent.provider.stub_response('Two.')
    runtime.ask('hello')
    branch = 'feature'
    runtime.prompt('again') { |event| event }

    assert_includes runtime.agent.provider.calls.last[:messages].first[:content], 'Branch: feature'
  end

  it 'keeps one system message across turns' do
    sections = Riffer::Rig::Extension.new('sections') { |rig| rig.prompt(:branch) { 'Branch: main' } }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [sections])
    runtime.agent.provider.stub_response('One.')
    runtime.agent.provider.stub_response('Two.')
    runtime.ask('hello')
    runtime.ask('again')

    roles = runtime.agent.provider.calls.last[:messages].map { |message| message[:role].to_s }

    assert_equal %w[system user assistant user], roles
  end

  it 'lets a later registration of the same section name win' do
    earlier = Riffer::Rig::Extension.new('earlier') { |rig| rig.prompt(:branch) { 'EARLIER' } }
    later = Riffer::Rig::Extension.new('later') { |rig| rig.prompt(:branch) { 'LATER' } }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [earlier, later])
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    refute_includes runtime.agent.provider.calls.last[:messages].first[:content], 'EARLIER'
  end

  it 'passes the runtime to a section' do
    sections = Riffer::Rig::Extension.new('sections') { |rig| rig.prompt(:cwd) { |ctx| "In #{ctx.cwd}" } }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [sections], cwd: '/tmp/proj')
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_includes runtime.agent.provider.calls.last[:messages].first[:content], 'In /tmp/proj'
  end

  it 'skips a section that renders nothing' do
    sections = Riffer::Rig::Extension.new('sections') { |rig| rig.prompt(:skills) { nil } }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [sections], instructions: 'CUSTOM_BASE')
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_match(/\ACUSTOM_BASE\n\nCurrent date: /, runtime.agent.provider.calls.last[:messages].first[:content])
  end

  it 'appends sections and the environment block under custom instructions' do
    sections = Riffer::Rig::Extension.new('sections') { |rig| rig.prompt(:branch) { 'Branch: main' } }
    runtime = Riffer::Rig::Runtime.new(
      'mock/test',
      extensions: [sections],
      instructions: 'CUSTOM_BASE',
      cwd: '/tmp/proj'
    )
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_equal "CUSTOM_BASE\n\nBranch: main\n\nCurrent date: #{Date.today}\nCurrent working directory: /tmp/proj",
                 runtime.agent.provider.calls.last[:messages].first[:content]
  end

  it 'raises on a second prompt while one runs' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('first')

    assert_raises(Riffer::Rig::Runtime::BusyError) do
      runtime.prompt('hello') do
        runtime.prompt('second').each { |event| event }
      end
    end
  end

  it 'is usable again after a turn ends' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('first')
    runtime.agent.provider.stub_response('second')
    runtime.prompt('hello').each { |event| event }

    assert_equal 'second', runtime.prompt('hello').find { |event| event.is_a?(Riffer::StreamEvents::TextDone) }.content
  end

  it 'mints a uuid_v7 id at construction' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}\z/, runtime.id)
  end

  it 'gives each runtime its own id' do
    one = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    two = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])

    refute_equal one.id, two.id
  end

  it 'opens every prompt with a session_start' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    first = runtime.prompt('hello').first

    assert_equal(Riffer::Rig::Events::SessionStart.new(runtime.id, :new), first)
  end

  it 'emits session_start once, not on every prompt' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('first')
    runtime.agent.provider.stub_response('second')
    runtime.prompt('hello').each { |event| event }
    second = runtime.prompt('hello').first

    refute_instance_of Riffer::Rig::Events::SessionStart, second
  end

  it 'closes every prompt with a turn_end' do
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.', token_usage: usage)

    last = nil
    runtime.prompt('hello') { |event| last = event }

    assert_equal(Riffer::Rig::Events::TurnEnd.new(:completed, usage), last)
  end

  it 'leaves turn_end cost nil without pricing' do
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.', token_usage: usage)

    last = nil
    runtime.prompt('hello') { |event| last = event }

    assert_nil last.cost
  end

  it 'reports a max_steps run in turn_end' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read], max_steps: 1)
    runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
    runtime.agent.provider.stub_response('second response')

    last = nil
    runtime.prompt('go') { |event| last = event }

    assert_equal :max_steps, last.stop_reason
  end

  it 'closes a runtime and refuses further prompts' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.close

    assert_raises(Riffer::Rig::Runtime::ClosedError) { runtime.prompt('hello') }
  end

  it 'closes a runtime and refuses further asks' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.close

    assert_raises(Riffer::Rig::Runtime::ClosedError) { runtime.ask('hello') }
  end

  it 'wraps the given host' do
    host = Class.new(Riffer::Rig::Hosts::Null) { define_method(:capabilities) { Set[:notify].freeze } }.new
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], host: host)

    assert_equal Set[:notify], runtime.host.capabilities
  end

  it 'mirrors host.notify as a notify event on the stream' do
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
    runtime.agent.provider.stub_response('All done.')

    notify_events = []
    runtime.host.notify('boom', level: :error)
    runtime.prompt('hello') { |event| notify_events << event if event.is_a?(Riffer::Rig::Events::Notify) }

    assert_equal [Riffer::Rig::Events::Notify.new('boom', :error)], notify_events
  end

  describe '#model' do
    it 'is the model the Runtime was built with' do
      assert_equal 'mock/test', Riffer::Rig::Runtime.new('mock/test').model
    end

    it 'is the override after assignment' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      runtime.model = 'mock/other'

      assert_equal 'mock/other', runtime.model
    end

    it 'keeps the session across an assignment' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      session = runtime.agent.session
      runtime.model = 'mock/other'

      assert_same session, runtime.agent.session
    end

    it 'keeps the model when the assignment names an unknown provider' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      begin
        runtime.model = 'acme/fast'
      rescue Riffer::ArgumentError
        nil
      end

      assert_equal 'mock/test', runtime.model
    end
  end

  describe '#on_model_change' do
    it 'notifies its observers on a switch' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      seen = []
      runtime.on_model_change { |model| seen << model }
      runtime.model = 'mock/other'

      assert_equal ['mock/other'], seen
    end

    it 'does not notify for the model the Runtime was built with' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      seen = []
      runtime.on_model_change { |model| seen << model }

      assert_empty seen
    end
  end

  describe '#tally' do
    before do
      @riffer_config = Riffer.config
      # Riffer's providers price usage from the global Riffer.config, so the
      # tests swap in a fresh one rather than leak pricing into other tests.
      Riffer.instance_variable_set(:@config, Riffer::Config.new)
    end

    after do
      Riffer.instance_variable_set(:@config, @riffer_config)
    end

    def priced_runtime(pricing)
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], pricing: pricing)
      runtime.agent.provider.stub_response(
        'One.', token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 1_000_000, output_tokens: 200_000)
      )
      runtime.agent.provider.stub_response(
        'Two.',
        token_usage: Riffer::Providers::TokenUsage.new(
          input_tokens: 2_000_000, output_tokens: 100_000, cache_write_tokens: 500_000, cache_read_tokens: 1_000_000
        )
      )
      runtime
    end

    def pricing
      { 'mock/test' => Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3) }
    end

    it 'is nil before the first turn' do
      assert_nil priced_runtime(pricing).tally
    end

    it 'sums usage across turns' do
      runtime = priced_runtime(pricing)
      runtime.ask('hello')
      runtime.prompt('again') { |event| event }

      assert_equal(
        { input_tokens: 3_000_000, output_tokens: 300_000, cache_write_tokens: 500_000, cache_read_tokens: 1_000_000 },
        runtime.tally.to_h.except(:cost)
      )
    end

    it 'prices a turn in USD per million tokens' do
      assert_in_delta 6.0, priced_runtime(pricing).ask('hello').token_usage.cost
    end

    it 'sums the cost across turns' do
      runtime = priced_runtime(pricing)
      runtime.ask('hello')
      runtime.prompt('again') { |event| event }

      assert_in_delta 11.175, runtime.tally.cost
    end

    it 'leaves a turn unpriced without a pricing entry' do
      assert_nil priced_runtime({ 'other/model' => pricing['mock/test'] }).ask('hello').token_usage.cost
    end

    it 'leaves the total unpriced without a pricing entry' do
      runtime = priced_runtime({})
      runtime.ask('hello')

      assert_nil runtime.tally.cost
    end

    it 'carries the turn usage on turn_end' do
      last = nil
      response = priced_runtime(pricing).prompt('hello').each { |event| last = event }

      assert_same response.token_usage, last.usage
    end

    it 'carries the turn cost on turn_end' do
      last = nil
      response = priced_runtime(pricing).prompt('hello').each { |event| last = event }

      assert_in_delta response.token_usage.cost, last.cost
    end
  end

  it 'registers its pricing into the riffer config it is given' do
    riffer_config = Riffer::Config.new
    pricing = { 'mock/test' => Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 0.0, cache_read: 0.0) }
    Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], pricing: pricing, riffer_config: riffer_config)

    assert_in_delta 3.0, riffer_config.pricing.rates_for('mock/test').input
  end

  describe '#cancel' do
    before do
      started = @started = Queue.new
      release = @release = Queue.new
      gate = Class.new(Riffer::Tool) do
        identifier 'gate'
        description 'Blocks until the test releases it'

        define_method(:call) do |**|
          started << true
          release.pop
          text('released')
        end
      end
      @gate_extension = Riffer::Rig.extension('test_runtime_cancel') { |rig| rig.tool gate }
      @runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@gate_extension])
      @runtime.agent.provider.stub_response(
        '', tool_calls: [{ name: 'gate', arguments: '{}' }, { name: 'gate', arguments: '{}' }]
      )
      @runtime.agent.provider.stub_response('after the cancel')
    end

    after do
      Riffer::Rig.instance_variable_get(:@extensions).delete('test_runtime_cancel')
    end

    def cancel_mid_tool
      Thread.new do
        @started.pop
        @runtime.cancel
        @release.close
      end
    end

    def cancelled_turn_events
      canceller = cancel_mid_tool
      events = []
      @runtime.prompt('go') { |event| events << event }
      canceller.join
      events
    end

    it 'ends the turn with the cancelled stop reason' do
      assert_equal :cancelled, cancelled_turn_events.last.stop_reason
    end

    it 'emits the riffer interrupt event with the cancelled reason' do
      interrupt = cancelled_turn_events.find { |event| event.is_a?(Riffer::StreamEvents::Interrupt) }

      assert_equal :cancelled, interrupt.reason
    end

    it 'heals the tool calls the cancel orphaned' do
      cancelled_turn_events
      healed = @runtime.agent.session.messages.grep(Riffer::Messages::Tool).find do |message|
        message.tool_call_id == 'mock_call_1'
      end

      assert_equal :interrupted, healed.error_type
    end

    it 'prompts again after a cancelled turn' do
      cancelled_turn_events

      assert_equal :completed, @runtime.ask('again').outcome.reason
    end

    it 'reports a cancelled ask as interrupted with the cancelled detail' do
      canceller = cancel_mid_tool
      outcome = @runtime.ask('go').outcome
      canceller.join

      assert_equal [:interrupted, 'cancelled'], [outcome.reason, outcome.detail]
    end

    it 'returns nil' do
      assert_nil @runtime.cancel
    end

    it 'is a no-op when idle' do
      @release.close
      @runtime.cancel

      assert_equal :completed, @runtime.ask('go').outcome.reason
    end
  end

  describe 'commands' do
    before do
      @git = Riffer::Rig::Extension.new('git') do |rig|
        rig.command('log', description: 'Recent commits') { |ctx| ctx.say("commits: #{ctx.args}") }
        rig.command('review', description: 'Review the diff') { |ctx| ctx.prompt("Review this diff: #{ctx.args}") }
        rig.command('depth', description: 'Show the depth') { |ctx| ctx.say(ctx.settings.fetch(:depth, 'none').to_s) }
        rig.command('boom', description: 'Always fails') { |_ctx| raise 'kaboom' }
        rig.command('which', description: 'Ask a question') { |ctx| ctx.say(ctx.ask('Which branch?').inspect) }
      end
      @other = Riffer::Rig::Extension.new('other') do |rig|
        rig.command('hello', description: 'Say hello') { |ctx| ctx.say('hello') }
      end
    end

    def command_events(runtime, name, args = '')
      events = []
      runtime.run_command(name, args) { |event| events << event }
      events
    end

    it 'lists names and descriptions in load order' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git, @other])

      assert_equal(
        [['log', 'Recent commits'], ['review', 'Review the diff'], ['depth', 'Show the depth'],
         ['boom', 'Always fails'], ['which', 'Ask a question'], ['hello', 'Say hello']],
        runtime.commands.reject { |command| command.extension == 'core' }
               .map { |command| [command.name, command.description] }
      )
    end

    it 'lets a later extension replace a command of the same name' do
      later = Riffer::Rig::Extension.new('later') { |rig| rig.command('log', description: 'Later log') { |_ctx| nil } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git, later])

      assert_equal 'Later log', runtime.commands.find { |command| command.name == 'log' }.description
    end

    it 'emits a command_output event from ctx.say' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal [Riffer::Rig::Events::CommandOutput.new('log', 'commits: -n 3')],
                   command_events(runtime, 'log', '-n 3')
    end

    it 'sends a user turn to the model from ctx.prompt' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.agent.provider.stub_response('Looks fine.')
      command_events(runtime, 'review', 'HEAD~1')

      assert_equal 'Review this diff: HEAD~1', runtime.agent.provider.calls.last[:messages].last[:content]
    end

    it 'streams the turn ctx.prompt runs to the block' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.agent.provider.stub_response('Looks fine.')

      assert_equal :completed, command_events(runtime, 'review').grep(Riffer::Rig::Events::TurnEnd).first.stop_reason
    end

    it 'reads the extension namespace of the settings' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git], settings: { git: { depth: 3 } })

      assert_equal [Riffer::Rig::Events::CommandOutput.new('depth', '3')], command_events(runtime, 'depth')
    end

    it 'gives an empty settings namespace to an extension with none' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal [Riffer::Rig::Events::CommandOutput.new('depth', 'none')], command_events(runtime, 'depth')
    end

    it 'returns nil from ctx.ask under the null host' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal [Riffer::Rig::Events::CommandOutput.new('which', 'nil')], command_events(runtime, 'which')
    end

    it 'returns nil' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_nil runtime.run_command('log', '')
    end

    it 'reports a raising command through notify' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal [Riffer::Rig::Events::Notify.new('Command boom failed: kaboom', :error)],
                   command_events(runtime, 'boom')
    end

    it 'stays usable after a raising command' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.agent.provider.stub_response('All done.')
      command_events(runtime, 'boom')

      assert_equal :completed, runtime.ask('hello').outcome.reason
    end

    it 'reports an unknown command through notify' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal [Riffer::Rig::Events::Notify.new('Unknown command: nope', :error)], command_events(runtime, 'nope')
    end

    it 'raises while a prompt runs' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.agent.provider.stub_response('All done.')

      assert_raises(Riffer::Rig::Runtime::BusyError) do
        runtime.prompt('hello') { runtime.run_command('log', '') }
      end
    end

    it 'keeps the Runtime busy after refusing a nested command' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.agent.provider.stub_response('All done.')

      assert_raises(Riffer::Rig::Runtime::BusyError) do
        runtime.prompt('hello') do
          runtime.run_command('log', '')
        rescue Riffer::Rig::Runtime::BusyError
          runtime.ask('second')
        end
      end
    end

    it 'refuses a prompt from inside a command and reports it' do
      nested = Riffer::Rig::Extension.new('nested') do |rig|
        rig.command('nest', description: 'Prompt the runtime directly') { |ctx| ctx.runtime.ask('hi') }
      end
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [nested])

      assert_equal 'Command nest failed: a prompt is already running on this Runtime',
                   command_events(runtime, 'nest').first.message
    end

    it 'refuses a command on a closed Runtime' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])
      runtime.close

      assert_raises(Riffer::Rig::Runtime::ClosedError) { runtime.run_command('log', '') }
    end

    describe '#install_command' do
      it 'keeps an installed command through a rebuild' do
        runtime = Riffer::Rig::Runtime.new('mock/test')
        command = Riffer::Rig::Command.new('reload', description: 'Reload', extension: 'core') { |_ctx| nil }
        runtime.install_command(command)
        runtime.rebuild(extensions: [], settings: {})

        assert_equal(command, runtime.commands.find { |candidate| candidate.name == 'reload' })
      end

      it 'lets an extension command replace an installed one' do
        runtime = Riffer::Rig::Runtime.new('mock/test')
        command = Riffer::Rig::Command.new('log', description: 'Installed log', extension: 'core') { |_ctx| nil }
        runtime.install_command(command)
        runtime.rebuild(extensions: [@git], settings: {})

        assert_equal 'Recent commits', runtime.commands.find { |candidate| candidate.name == 'log' }.description
      end
    end
  end

  describe 'extension load errors' do
    before do
      @first = Riffer::Rig::Extension.new('first') { |rig| rig.tool Riffer::Rig::Tools::Read }
      @broken = Riffer::Rig::Extension.new('broken') do |rig|
        rig.tool Riffer::Rig::Tools::Write
        raise 'kaboom'
      end
      @last = Riffer::Rig::Extension.new('last') { |rig| rig.tool Riffer::Rig::Tools::Bash }
      @runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@first, @broken, @last])
    end

    it 'registers the extensions around a raising one' do
      assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Bash], @runtime.agent.tools
    end

    it 'records the raising extension on errors' do
      assert_equal([[@broken, 'kaboom']], @runtime.errors.map { |failure| [failure.extension, failure.error.message] })
    end

    it 'reports the failure with one notify at error level' do
      @runtime.agent.provider.stub_response('All done.')

      assert_equal [Riffer::Rig::Events::Notify.new('Extension broken failed to load: kaboom', :error)],
                   @runtime.prompt('hello').grep(Riffer::Rig::Events::Notify)
    end

    it 'keeps the error out of the model context' do
      @runtime.agent.provider.stub_response('All done.')
      @runtime.ask('hello')

      refute_includes @runtime.agent.provider.calls.last[:messages].to_s, 'kaboom'
    end

    it 'reports an unmet requires as a load error' do
      future = Riffer::Rig::Extension.new('future', requires: '>= 99') { |rig| rig.tool Riffer::Rig::Tools::Edit }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [future])
      runtime.agent.provider.stub_response('All done.')

      assert_equal(
        [Riffer::Rig::Events::Notify.new(
          "Extension future failed to load: extension future requires riffer-rig >= 99, found #{Riffer::Rig::VERSION}",
          :error
        )],
        runtime.prompt('hello').grep(Riffer::Rig::Events::Notify)
      )
    end

    it 'skips an extension whose requires is unmet' do
      future = Riffer::Rig::Extension.new('future', requires: '>= 99') { |rig| rig.tool Riffer::Rig::Tools::Edit }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [future])

      assert_empty runtime.agent.tools
    end

    it 'loads an extension whose requires is met' do
      current = Riffer::Rig::Extension.new('current', requires: "= #{Riffer::Rig::VERSION}") do |rig|
        rig.tool Riffer::Rig::Tools::Edit
      end
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [current])

      assert_equal [Riffer::Rig::Tools::Edit], runtime.agent.tools
    end

    it 'records no errors when every extension loads' do
      assert_empty Riffer::Rig::Runtime.new('mock/test', extensions: [@first, @last]).errors
    end
  end

  describe 'bundled extensions' do
    def read_in(dir)
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [Riffer::Rig.bundled(:read)], cwd: dir)
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"note.txt"}' }])
      runtime.agent.provider.stub_response('Done.')
      runtime.ask('read note.txt').messages.find { |message| message.is_a?(Riffer::Messages::Tool) }.content
    end

    def replaced_bash
      Class.new(Riffer::Tool) do
        identifier 'bash'
        description 'A sandboxed shell'
      end
    end

    it 'reads the same relative path from each runtime cwd' do
      Dir.mktmpdir do |one|
        Dir.mktmpdir do |two|
          File.write(File.join(one, 'note.txt'), 'from one')
          File.write(File.join(two, 'note.txt'), 'from two')

          assert_equal ["     1\tfrom one", "     1\tfrom two"], [read_in(one), read_in(two)]
        end
      end
    end

    it 'lets a later extension replace a bundled tool by identifier' do
      sandbox = replaced_bash
      replacement = Riffer::Rig::Extension.new('sandbox') { |rig| rig.tool sandbox }
      tools = %i[read write edit bash].map { |name| Riffer::Rig.bundled(name) }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [*tools, replacement])

      assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Write, Riffer::Rig::Tools::Edit, sandbox],
                   runtime.agent.tools
    end

    it 'reports the replaced tool through notify at info level' do
      sandbox = replaced_bash
      replacement = Riffer::Rig::Extension.new('sandbox') { |rig| rig.tool sandbox }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [Riffer::Rig.bundled(:bash), replacement])

      assert_equal [Riffer::Rig::Events::Notify.new('Extension sandbox replaces tool bash from bash', :info)],
                   runtime.host.drain
    end

    it 'keeps the bundled original reachable after a replacement' do
      sandbox = replaced_bash
      replacement = Riffer::Rig::Extension.new('sandbox') { |rig| rig.tool sandbox }
      Riffer::Rig::Runtime.new('mock/test', extensions: [Riffer::Rig.bundled(:bash), replacement])
      registrar = Riffer::Rig::Registrar.new('bash')
      Riffer::Rig.bundled(:bash).run(registrar)

      assert_equal [Riffer::Rig::Tools::Bash], registrar.tools.values
    end

    it 'reports a replaced command through notify' do
      earlier = Riffer::Rig::Extension.new('earlier') { |rig| rig.command('log', description: 'a') { |_ctx| nil } }
      later = Riffer::Rig::Extension.new('later') { |rig| rig.command('log', description: 'b') { |_ctx| nil } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [earlier, later])

      assert_equal [Riffer::Rig::Events::Notify.new('Extension later replaces command log from earlier', :info)],
                   runtime.host.drain
    end

    it 'reports a replaced prompt section through notify' do
      earlier = Riffer::Rig::Extension.new('earlier') { |rig| rig.prompt(:branch) { 'a' } }
      later = Riffer::Rig::Extension.new('later') { |rig| rig.prompt(:branch) { 'b' } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [earlier, later])

      notice = Riffer::Rig::Events::Notify.new('Extension later replaces prompt section branch from earlier', :info)

      assert_equal [notice], runtime.host.drain
    end

    it 'notifies nothing when no registration is replaced' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: Riffer::Rig.bundled)

      assert_empty runtime.host.drain
    end
  end

  describe 'declared settings' do
    before do
      @git = Riffer::Rig::Extension.new('git') do |rig|
        rig.setting :depth, default: 3
        rig.setting :remote, default: 'origin'
        rig.command('show', description: 'Show the settings') { |ctx| ctx.say(ctx.settings.inspect) }
      end
    end

    def settings_output(runtime)
      events = []
      runtime.run_command('show') { |event| events << event }
      events.first.text
    end

    it 'applies a declared default when the settings lack the key' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git])

      assert_equal({ depth: 3, remote: 'origin' }.inspect, settings_output(runtime))
    end

    it 'lets a provided value override the declared default' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git], settings: { git: { depth: 10 } })

      assert_equal({ depth: 10, remote: 'origin' }.inspect, settings_output(runtime))
    end

    it 'shows a command only its own namespace' do
      runtime = Riffer::Rig::Runtime.new(
        'mock/test', extensions: [@git], settings: { model: 'mock/other', other: { depth: 1 } }
      )

      assert_equal({ depth: 3, remote: 'origin' }.inspect, settings_output(runtime))
    end

    it 'exposes the merged settings with declared defaults filled in' do
      runtime = Riffer::Rig::Runtime.new(
        'mock/test', extensions: [@git], settings: { model: 'mock/other', git: { depth: 10 } }
      )

      assert_equal({ model: 'mock/other', git: { depth: 10, remote: 'origin' } }, runtime.settings)
    end

    it 'exposes a table of declared keys per extension' do
      bare = Riffer::Rig::Extension.new('bare') { |rig| rig.tool Riffer::Rig::Tools::Read }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@git, bare])

      assert_equal({ 'git' => { depth: 3, remote: 'origin' } }, runtime.declared_settings)
    end

    it 'rejects extensions named after core settings keys' do
      colliding = %w[reasoning model].map { |name| Riffer::Rig::Extension.new(name) { |rig| rig.tool Riffer::Rig::Tools::Read } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: colliding)

      assert_empty runtime.agent.tools
    end

    it 'records a colliding extension on errors' do
      reasoning = Riffer::Rig::Extension.new('reasoning') { |rig| rig.setting :level, default: 'low' }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [reasoning])

      assert_equal(
        [[reasoning, Riffer::Rig::Registrar::NameCollisionError]],
        runtime.errors.map { |failure| [failure.extension, failure.error.class] }
      )
    end

    it 'reports a colliding extension through notify' do
      model = Riffer::Rig::Extension.new('model') { |rig| rig.setting :name, default: 'x' }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [model])
      runtime.agent.provider.stub_response('All done.')

      notice = 'Extension model failed to load: extension name model collides with a core settings key'

      assert_equal [Riffer::Rig::Events::Notify.new(notice, :error)],
                   runtime.prompt('hello').grep(Riffer::Rig::Events::Notify)
    end

    it 'leaves the core settings key untouched by a colliding extension' do
      model = Riffer::Rig::Extension.new('model') { |rig| rig.setting :name, default: 'x' }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [model], settings: { model: 'mock/other' })

      assert_equal({ model: 'mock/other' }, runtime.settings)
    end
  end

  describe 'hooks' do
    before do
      echo = Class.new(Riffer::Tool) do
        identifier 'echo'
        description 'Echoes its text'

        params do
          required :text, String
        end

        define_method(:call) { |context:, text:| text("echo: #{text}") } # rubocop:disable Lint/UnusedBlockArgument -- riffer passes context: to every call
      end
      @echo = Riffer::Rig::Extension.new('echo') { |rig| rig.tool echo }
    end

    def runtime_with(&)
      Riffer::Rig::Runtime.new('mock/test', extensions: [@echo, Riffer::Rig::Extension.new('hooks', &)])
    end

    def stub_tool_turn(runtime, text = 'hi')
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'echo', arguments: { text: text }.to_json }])
      runtime.agent.provider.stub_response('All done.')
    end

    def tool_result(runtime)
      runtime.agent.session.messages.grep(Riffer::Messages::Tool).last
    end

    it 'turns a blocked tool call into a tool error the model sees' do
      runtime = runtime_with { |rig| rig.on(:before_tool_call) { |_e| next :block, 'no echoes' } }
      stub_tool_turn(runtime)
      runtime.ask('go')
      sent = runtime.agent.provider.calls.last[:messages].find { |message| message[:role].to_s == 'tool' }

      assert_equal 'no echoes', sent[:content]
    end

    it 'marks a blocked tool call as an error' do
      runtime = runtime_with { |rig| rig.on(:before_tool_call) { |_e| next :block, 'no echoes' } }
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal :blocked, tool_result(runtime).error_type
    end

    it 'feeds a replacement tool payload to the next hook' do
      seen = nil
      runtime = runtime_with do |rig|
        rig.on(:before_tool_call) { |e| e.args.merge(text: 'replaced') }
        rig.on(:before_tool_call) { |e| seen = e.args[:text] }
      end
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal 'replaced', seen
    end

    it 'runs the tool with the replacement payload' do
      runtime = runtime_with { |rig| rig.on(:before_tool_call) { |e| e.args.merge(text: 'replaced') } }
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal 'echo: replaced', tool_result(runtime).content
    end

    it 'fires before_request before each LLM call in a two-step tool turn' do
      count = 0
      runtime = runtime_with { |rig| rig.on(:before_request) { |_e| count += 1 } }
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal 2, count
    end

    it 'fires the second before_request after the tool result' do
      last = nil
      runtime = runtime_with { |rig| rig.on(:before_request) { |e| last = e.messages.last } }
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_instance_of Riffer::Messages::Tool, last
    end

    it 'sends a replacement request payload to the model' do
      runtime = runtime_with do |rig|
        rig.on(:before_request) do |e|
          next unless e.messages.last.is_a?(Riffer::Messages::Tool)

          [*e.messages, Riffer::Messages::User.new('MID_TURN_NOTE')]
        end
      end
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal 'MID_TURN_NOTE', runtime.agent.provider.calls.last[:messages].last[:content]
    end

    it 'blocks the first request as a guardrail block' do
      runtime = runtime_with { |rig| rig.on(:before_request) { |_e| next :block, 'offline' } }
      runtime.agent.provider.stub_response('All done.')

      assert_equal :guardrail_blocked, runtime.ask('go').outcome.reason
    end

    it 'interrupts the turn when a later request is blocked' do
      runtime = runtime_with do |rig|
        rig.on(:before_request) { |e| next :block, 'enough' if e.messages.last.is_a?(Riffer::Messages::Tool) }
      end
      stub_tool_turn(runtime)
      outcome = runtime.ask('go').outcome

      assert_equal [:interrupted, 'enough'], [outcome.reason, outcome.detail]
    end

    it 'sends a replacement prompt to the model' do
      runtime = runtime_with { |rig| rig.on(:before_prompt) { |e| "#{e.text} (be brief)" } }
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('go')

      assert_equal 'go (be brief)', runtime.agent.provider.calls.last[:messages].last[:content]
    end

    it 'never calls the model for a blocked prompt' do
      runtime = runtime_with { |rig| rig.on(:before_prompt) { |_e| next :block, 'not now' } }
      runtime.ask('go')

      assert_empty runtime.agent.provider.calls
    end

    it 'keeps a blocked prompt out of the session' do
      runtime = runtime_with { |rig| rig.on(:before_prompt) { |_e| next :block, 'not now' } }
      runtime.ask('go')

      assert_empty runtime.agent.session.messages.grep(Riffer::Messages::User)
    end

    it 'ends a blocked prompt with a guardrail_blocked turn_end' do
      runtime = runtime_with { |rig| rig.on(:before_prompt) { |_e| next :block, 'not now' } }
      last = nil
      runtime.prompt('go') { |event| last = event }

      assert_equal :guardrail_blocked, last.stop_reason
    end

    it 'tells the host why a prompt was blocked' do
      runtime = runtime_with { |rig| rig.on(:before_prompt) { |_e| next :block, 'not now' } }
      notifies = runtime.prompt('go').grep(Riffer::Rig::Events::Notify)

      assert_equal [Riffer::Rig::Events::Notify.new('not now', :warning)], notifies
    end

    it 'ignores what after_tool_call returns' do
      runtime = runtime_with { |rig| rig.on(:after_tool_call) { |_e| 'IGNORED' } }
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal 'echo: hi', tool_result(runtime).content
    end

    it 'hands after_tool_call the tool result' do
      result = nil
      runtime = runtime_with { |rig| rig.on(:after_tool_call) { |e| result = e.result.content } }
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal 'echo: hi', result
    end

    it 'ignores what after_response returns' do
      runtime = runtime_with { |rig| rig.on(:after_response) { |_e| 'IGNORED' } }
      runtime.agent.provider.stub_response('All done.')

      assert_equal 'All done.', runtime.ask('go').content
    end

    it 'fires after_response once per model response' do
      count = 0
      runtime = runtime_with { |rig| rig.on(:after_response) { |_e| count += 1 } }
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal 2, count
    end

    it 'ignores what turn_end returns' do
      runtime = runtime_with { |rig| rig.on(:turn_end) { |_e| :block } }
      runtime.agent.provider.stub_response('All done.')
      last = nil
      runtime.prompt('go') { |event| last = event }

      assert_equal :completed, last.stop_reason
    end

    it 'fires turn_end on ask as well as prompt' do
      reasons = []
      runtime = runtime_with { |rig| rig.on(:turn_end) { |e| reasons << e.stop_reason } }
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('go')

      assert_equal [:completed], reasons
    end

    it 'shows stream hooks every riffer stream event, unchanged' do
      seen = []
      runtime = runtime_with { |rig| rig.on(:stream) { |e| seen << e } }
      stub_tool_turn(runtime)
      streamed = runtime.prompt('go').grep(Riffer::StreamEvents::Base)

      assert_equal streamed.map(&:object_id), seen.map(&:object_id)
    end

    it 'fires session_start with the new reason' do
      events = []
      runtime = runtime_with { |rig| rig.on(:session_start) { |e| events << e } }
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('go')

      assert_equal [Riffer::Rig::Events::SessionStart.new(runtime.id, :new)], events
    end

    it 'fires session_start once across turns' do
      count = 0
      runtime = runtime_with { |rig| rig.on(:session_start) { |_e| count += 1 } }
      runtime.agent.provider.stub_response('One.')
      runtime.agent.provider.stub_response('Two.')
      runtime.ask('go')
      runtime.ask('again')

      assert_equal 1, count
    end

    it 'fires session_end with the close reason' do
      events = []
      runtime = runtime_with { |rig| rig.on(:session_end) { |e| events << e } }
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('go')
      runtime.close
      runtime.close

      assert_equal [Riffer::Rig::Events::SessionEnd.new(:close)], events
    end

    it 'skips session_end for a session that never started' do
      events = []
      runtime = runtime_with { |rig| rig.on(:session_end) { |e| events << e } }
      runtime.close

      assert_empty events
    end

    it 'reports a raising hook through notify' do
      runtime = runtime_with { |rig| rig.on(:before_tool_call) { |_e| raise 'boom' } }
      stub_tool_turn(runtime)
      notifies = runtime.prompt('go').grep(Riffer::Rig::Events::Notify)

      assert_equal [Riffer::Rig::Events::Notify.new('before_tool_call hook failed: boom', :error)], notifies
    end

    it 'continues the turn after a hook raises' do
      runtime = runtime_with { |rig| rig.on(:before_tool_call) { |_e| raise 'boom' } }
      stub_tool_turn(runtime)
      runtime.ask('go')

      assert_equal 'echo: hi', tool_result(runtime).content
    end

    it 'runs hooks in load order across extensions' do
      order = []
      first = Riffer::Rig::Extension.new('first') { |rig| rig.on(:before_prompt) { |_e| order << :first } }
      second = Riffer::Rig::Extension.new('second') { |rig| rig.on(:before_prompt) { |_e| order << :second } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [second, first])
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('go')

      assert_equal %i[second first], order
    end
  end

  describe 'snapshots' do
    def usage(input, output)
      Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output)
    end

    def saved_runtime
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
      runtime.agent.provider.stub_response('Hi there.', token_usage: usage(10, 5))
      runtime.ask('hello')
      runtime
    end

    def restored(snapshot, **)
      Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], snapshot: snapshot, **)
    end

    def with_orphaned_tail(snapshot)
      call = Riffer::Messages::Assistant::ToolCall.new(call_id: 'orphan', name: 'read', arguments: '{"path":"/tmp/x"}')
      snapshot.merge(messages: [*snapshot[:messages], Riffer::Messages::Assistant.new('', tool_calls: [call]).to_h])
    end

    def first_prompt_events(runtime)
      runtime.agent.provider.stub_response('Again.')
      runtime.prompt('again').to_a
    end

    it 'holds the id, messages, model override and activated skills' do
      assert_equal %i[id messages model skills], saved_runtime.to_h.keys
    end

    it 'holds the messages as riffer hashes' do
      runtime = saved_runtime

      assert_equal runtime.agent.session.messages.map(&:to_h), runtime.to_h[:messages]
    end

    it 'holds no model without an override' do
      assert_nil saved_runtime.to_h[:model]
    end

    it 'holds the model override' do
      runtime = saved_runtime
      runtime.model = 'mock/other'

      assert_equal 'mock/other', runtime.to_h[:model]
    end

    it 'holds no skills while none are activated' do
      assert_empty saved_runtime.to_h[:skills]
    end

    it 'restores the id' do
      snapshot = saved_runtime.to_h

      assert_equal snapshot[:id], restored(snapshot).id
    end

    it 'continues the conversation after a restore' do
      runtime = restored(saved_runtime.to_h)
      runtime.agent.provider.stub_response('Welcome back.')
      runtime.ask('still there?')
      sent = runtime.agent.provider.calls.last[:messages].map { |message| message[:content] }

      assert_equal ['hello', 'Hi there.', 'still there?'], sent.drop(1)
    end

    it 'continues the conversation from a JSON round trip' do
      snapshot = JSON.parse(JSON.generate(saved_runtime.to_h), symbolize_names: true)
      runtime = restored(snapshot)
      runtime.agent.provider.stub_response('Welcome back.')

      assert_equal 'Welcome back.', runtime.ask('still there?').content
    end

    it 'opens the first prompt after a restore with session_start(reason: :restore)' do
      snapshot = saved_runtime.to_h
      first = first_prompt_events(restored(snapshot)).first

      assert_equal Riffer::Rig::Events::SessionStart.new(snapshot[:id], :restore), first
    end

    it 'delivers session_start(reason: :restore) to hooks' do
      reasons = []
      hooks = Riffer::Rig::Extension.new('restore_hooks') { |rig| rig.on(:session_start) { |e| reasons << e.reason } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [hooks], snapshot: saved_runtime.to_h)
      first_prompt_events(runtime)

      assert_equal [:restore], reasons
    end

    it 'heals an orphaned tail tool call with an interrupted result' do
      runtime = restored(with_orphaned_tail(saved_runtime.to_h))
      healed = runtime.agent.session.messages.last

      assert_equal ['orphan', :interrupted], [healed.tool_call_id, healed.error_type]
    end

    it 'applies the saved model when its provider has credentials' do
      runtime = saved_runtime
      runtime.model = 'mock/other'

      assert_equal 'mock/other', restored(runtime.to_h, credentials: { mock: {} }).model
    end

    it 'keeps the saved model as the override of the restored Runtime' do
      runtime = saved_runtime
      runtime.model = 'mock/other'

      assert_equal 'mock/other', restored(runtime.to_h, credentials: { mock: {} }).to_h[:model]
    end

    it 'uses the given model when the saved provider has no credentials' do
      runtime = saved_runtime
      runtime.model = 'mock/other'

      assert_equal 'mock/test', restored(runtime.to_h).model
    end

    it 'notifies once when the saved provider has no credentials' do
      runtime = saved_runtime
      runtime.model = 'mock/other'
      notifies = first_prompt_events(restored(runtime.to_h)).grep(Riffer::Rig::Events::Notify)

      assert_equal 1, notifies.length
    end

    it 'does not notify when there is no saved model' do
      notifies = first_prompt_events(restored(saved_runtime.to_h)).grep(Riffer::Rig::Events::Notify)

      assert_empty notifies
    end

    it 'restores the tally as the sum of the messages token usage' do
      runtime = saved_runtime
      runtime.agent.provider.stub_response('Second.', token_usage: usage(20, 7))
      runtime.ask('again')

      assert_equal usage(30, 12).to_h, restored(runtime.to_h).tally.to_h
    end

    it 'restores a nil tally when no message carries usage' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
      runtime.agent.provider.stub_response('No usage.')
      runtime.ask('hello')

      assert_nil restored(runtime.to_h).tally
    end
  end

  describe 'skills' do
    before do
      @skills_dir = Dir.mktmpdir
      write_skill(@skills_dir, 'a')
      @skills = Riffer::Rig::Extension.new('local_skills') do |rig|
        rig.skills { |_runtime| Riffer::Skills::FilesystemBackend.new(@skills_dir) }
      end
    end

    after do
      FileUtils.remove_entry(@skills_dir)
    end

    def write_skill(root, name)
      FileUtils.mkdir_p(File.join(root, name))
      File.write(File.join(root, name, 'SKILL.md'), "---\nname: #{name}\ndescription: #{name}.\n---\nDo #{name}.\n")
    end

    def skilled_runtime(**)
      Riffer::Rig::Runtime.new('mock/test', extensions: [@skills], **)
    end

    it 'passes the Runtime to a skills source' do
      seen = nil
      spy = Riffer::Rig::Extension.new('spy') do |rig|
        rig.skills do |runtime|
          seen = runtime
          Riffer::Skills::FilesystemBackend.new(@skills_dir)
        end
      end
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [spy])

      assert_same runtime, seen
    end

    it 'merges the skills of every source into the catalog' do
      other = Dir.mktmpdir
      write_skill(other, 'b')
      more = Riffer::Rig::Extension.new('more') { |rig| rig.skills { |_runtime| Riffer::Skills::FilesystemBackend.new(other) } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@skills, more])

      assert_equal %w[a b], runtime.agent.context.skills.skills.keys
    ensure
      FileUtils.remove_entry(other)
    end

    it 'records a skill the model activated' do
      runtime = skilled_runtime
      runtime.agent.context.skills.activate('a')

      assert_equal %w[a], runtime.to_h[:skills]
    end

    it 're-activates a snapshot skill by name on restore' do
      runtime = skilled_runtime
      runtime.agent.context.skills.activate('a')

      assert skilled_runtime(snapshot: runtime.to_h).agent.context.skills.activated?('a')
    end

    it 'drops a snapshot skill that no longer exists' do
      snapshot = skilled_runtime.to_h.merge(skills: %w[a gone])

      assert_equal %w[a], skilled_runtime(snapshot: snapshot).to_h[:skills]
    end

    it 'keeps activated skills across a model switch' do
      runtime = skilled_runtime
      runtime.agent.context.skills.activate('a')
      runtime.model = 'mock/other'

      assert_equal %w[a], runtime.to_h[:skills]
    end

    it 'lists a skill added before a rebuild' do
      runtime = skilled_runtime
      write_skill(@skills_dir, 'b')
      runtime.rebuild(extensions: [@skills], settings: {})

      assert_includes runtime.commands.map(&:name), 'skill:b'
    end

    it 'lets a later extension replace a skill command by name' do
      mine = Riffer::Rig::Extension.new('mine') { |rig| rig.command('skill:a', description: 'Mine') { |_ctx| nil } }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@skills, mine])

      assert_equal 'Mine', runtime.commands.find { |command| command.name == 'skill:a' }.description
    end
  end

  describe '#on_message' do
    it 'fires once per message the turn adds' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], tools: %w[read])
      observed = []
      runtime.on_message { |message| observed << message }
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('The file says hi.')
      runtime.ask('read /tmp/x')

      assert_equal runtime.agent.session.messages.drop(1), observed
    end

    it 'keeps firing once per message after a model switch' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
      observed = []
      runtime.on_message { |message| observed << message }
      runtime.model = 'mock/other'
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('hello')

      assert_equal 2, observed.length
    end

    it 'fires for a restored Runtime' do
      runtime = restored_for_observer
      observed = []
      runtime.on_message { |message| observed << message }
      runtime.agent.provider.stub_response('All done.')
      runtime.ask('hello')

      assert_equal ['hello', 'All done.'], observed.map(&:content)
    end

    def restored_for_observer
      saved = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension])
      Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], snapshot: saved.to_h)
    end
  end

  describe '#rebuild' do
    before do
      @lifecycle = []
      lifecycle = @lifecycle
      @old = Riffer::Rig::Extension.new('old') do |rig|
        rig.tool Riffer::Rig::Tools::Read
        rig.command('old', description: 'The old command') { |ctx| ctx.say('old') }
        rig.prompt(:section) { 'OLD_SECTION' }
        rig.on(:before_prompt) { |_e| lifecycle << :old_hook }
        rig.on(:session_end) { |e| lifecycle << [:old, e] }
      end
      @new = Riffer::Rig::Extension.new('new') do |rig|
        rig.tool Riffer::Rig::Tools::Bash
        rig.command('new', description: 'The new command') { |ctx| ctx.say('new') }
        rig.prompt(:section) { 'NEW_SECTION' }
        rig.on(:before_prompt) { |_e| lifecycle << :new_hook }
        rig.on(:session_start) { |e| lifecycle << [:new, e] }
      end
      @runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@old])
    end

    def started(runtime)
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 7, output_tokens: 3)
      runtime.agent.provider.stub_response('Before.', token_usage: usage)
      runtime.ask('before')
      runtime
    end

    def rebuilt(runtime = started(@runtime), extensions: [@new], settings: {})
      runtime.rebuild(extensions: extensions, settings: settings)
      runtime
    end

    def next_turn(runtime)
      runtime.agent.provider.stub_response('After.')
      runtime.prompt('after').to_a
    end

    it 'returns nil' do
      assert_nil @runtime.rebuild(extensions: [@new], settings: {})
    end

    it 'swaps in the tools of the new list' do
      assert_equal [Riffer::Rig::Tools::Bash], rebuilt.agent.tools
    end

    it 'swaps in the commands of the new list' do
      assert_equal %w[auth model new], rebuilt.commands.map(&:name)
    end

    it 'renders the prompt sections of the new list' do
      runtime = rebuilt
      next_turn(runtime)

      assert_includes runtime.agent.provider.calls.last[:messages].first[:content], 'NEW_SECTION'
    end

    it 'runs the hooks of the new list only' do
      runtime = rebuilt
      @lifecycle.clear
      next_turn(runtime)

      assert_equal [:new_hook], @lifecycle
    end

    it 'applies the new settings with the new declared defaults' do
      declaring = Riffer::Rig::Extension.new('git') { |rig| rig.setting :depth, default: 3 }

      runtime = rebuilt(extensions: [declaring], settings: { model: 'mock/other' })

      assert_equal({ model: 'mock/other', git: { depth: 3 } }, runtime.settings)
    end

    it 'keeps the message history' do
      runtime = started(@runtime)
      history = runtime.agent.session.messages.drop(1)

      assert_equal history, rebuilt(runtime).agent.session.messages.drop(1)
    end

    it 'keeps the tally' do
      assert_equal 10, rebuilt.tally.total_tokens
    end

    it 'keeps the /model override' do
      runtime = started(@runtime)
      runtime.model = 'mock/other'

      assert_equal 'mock/other', rebuilt(runtime, settings: { model: 'mock/test' }).model
    end

    it 'keeps the id' do
      id = @runtime.id

      assert_equal id, rebuilt.id
    end

    it 'keeps the host' do
      host = @runtime.host

      assert_same host, rebuilt.host
    end

    it 'keeps the tool allowlist' do
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@old], tools: %w[read])

      assert_empty rebuilt(runtime).agent.tools
    end

    it 'clears the load errors of the old list' do
      broken = Riffer::Rig::Extension.new('broken') { |_rig| raise 'kaboom' }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [broken])

      assert_empty rebuilt(runtime).errors
    end

    it 'fires session_end with the reload reason on the old hooks' do
      rebuilt

      assert_includes @lifecycle, [:old, Riffer::Rig::Events::SessionEnd.new(:reload)]
    end

    it 'fires session_start with the reload reason on the new hooks' do
      runtime = rebuilt

      assert_includes @lifecycle, [:new, Riffer::Rig::Events::SessionStart.new(runtime.id, :reload)]
    end

    it 'opens the next turn with session_end then session_start, both for the reload' do
      runtime = rebuilt

      session_end = Riffer::Rig::Events::SessionEnd.new(:reload)
      session_start = Riffer::Rig::Events::SessionStart.new(runtime.id, :reload)

      assert_equal [session_end, session_start], next_turn(runtime).take(2)
    end

    it 'leaves a session that never started to open with session_start new' do
      runtime = rebuilt(@runtime)

      assert_equal Riffer::Rig::Events::SessionStart.new(runtime.id, :new), next_turn(runtime).first
    end

    describe 'with a raising extension in the new list' do
      before do
        @broken = Riffer::Rig::Extension.new('broken') do |rig|
          rig.tool Riffer::Rig::Tools::Write
          raise 'kaboom'
        end
        started(@runtime)
      end

      def attempt
        @runtime.rebuild(extensions: [@new, @broken], settings: { model: 'mock/other' })
      rescue RuntimeError
        nil
      end

      it 'propagates the error' do
        assert_raises(RuntimeError) { @runtime.rebuild(extensions: [@new, @broken], settings: {}) }
      end

      it 'keeps the old tools' do
        attempt

        assert_equal [Riffer::Rig::Tools::Read], @runtime.agent.tools
      end

      it 'keeps the old commands' do
        attempt

        assert_equal %w[auth model old], @runtime.commands.map(&:name)
      end

      it 'keeps the old settings' do
        attempt

        assert_empty @runtime.settings
      end

      it 'fires no lifecycle hooks' do
        @lifecycle.clear
        attempt

        assert_empty @lifecycle
      end

      it 'releases the Runtime for the next rebuild' do
        attempt

        assert_nil @runtime.rebuild(extensions: [@new], settings: {})
      end
    end

    it 'rebuilds from inside a hook' do
      runtime = nil
      reloading = Riffer::Rig::Extension.new('reloading') do |rig|
        rig.on(:turn_end) { |_e| runtime.rebuild(extensions: [], settings: {}) }
      end
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [reloading])
      runtime.agent.provider.stub_response('All done.')
      runtime.prompt('go') { |event| event }

      assert_empty runtime.agent.tools
    end

    it 'rebuilds from inside a command' do
      reloading = Riffer::Rig::Extension.new('reloading') do |rig|
        rig.command('reload', description: 'Rebuild') { |ctx| ctx.runtime.rebuild(extensions: [], settings: {}) }
      end
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [reloading])
      runtime.run_command('reload')

      assert_empty runtime.agent.tools
    end

    it 'raises on a closed Runtime' do
      @runtime.close

      assert_raises(Riffer::Rig::Runtime::ClosedError) { @runtime.rebuild(extensions: [@new], settings: {}) }
    end

    describe 'providers' do
      before do
        @provider = Riffer::Rig::Extension.new('provider') do |_rig|
          Riffer::Providers::Repository.register(:rig_rebuild) { Riffer::Providers::Mock }
        end
        @on_provider = Riffer::Rig::Runtime.new('rig_rebuild/fast', extensions: [@provider])
      end

      after do
        Riffer::Providers::Repository.unregister(:rig_rebuild)
      end

      it 'keeps a provider registered before the rebuild' do
        assert_equal 'rig_rebuild/fast', rebuilt(@on_provider, extensions: []).model
      end

      it 're-registers a provider idempotently' do
        assert_equal 'rig_rebuild/fast', rebuilt(@on_provider, extensions: [@provider]).model
      end
    end
  end

  describe 'MCP servers' do
    before do
      @server = McpHttpsServer.new
      @ssl_cert_file = ENV.fetch('SSL_CERT_FILE', nil)
      ENV['SSL_CERT_FILE'] = @server.ca_file
      @runtimes = []
      @auth_dir = Dir.mktmpdir('rig-mcp-auth')
      @auth_path = File.join(@auth_dir, '.riffer', 'auth.json')
    end

    after do
      @runtimes.each(&:close)
      ENV['SSL_CERT_FILE'] = @ssl_cert_file
      @server.stop
      FileUtils.remove_entry(@auth_dir)
    end

    def serving(name = 'web', url: @server.url, headers: {}, auth: {})
      Riffer::Rig::Extension.new("serves_#{name}") { |rig| rig.mcp(name, url: url, headers: headers, auth: auth) }
    end

    def runtime(extensions, **)
      Riffer::Rig::Runtime.new('mock/test', extensions: extensions, **).tap { |built| @runtimes << built }
    end

    def tool_names(runtime)
      runtime.agent.tools.map(&:name)
    end

    def notifies(runtime)
      runtime.agent.provider.stub_response('Done.')
      runtime.prompt('go').grep(Riffer::Rig::Events::Notify)
    end

    def registration(name = 'web')
      Riffer::Mcp.registrations[name]
    end

    it 'reports a stdio server as unregistrable through notify at error level' do
      stdio = Riffer::Rig::Extension.new('serves_stdio') { |rig| rig.mcp('local', command: 'echo') }

      assert_equal(
        [Riffer::Rig::Events::Notify.new('MCP server local runs over stdio, which riffer cannot register yet', :error)],
        notifies(runtime([stdio]))
      )
    end

    it 'adds each server tool under riffer MCP naming' do
      assert_equal %w[web__echo web__token], tool_names(runtime([serving]))
    end

    it 'adds the server tools after the extension tools' do
      assert_equal %w[read web__echo web__token], tool_names(runtime([@extension, serving], tools: %w[read]))
    end

    it 'does not filter the server tools by the tools: allowlist' do
      assert_equal %w[web__echo web__token], tool_names(runtime([serving], tools: %w[web__echo]))
    end

    it 'runs a server tool the model calls' do
      built = runtime([serving])
      built.agent.provider.stub_response('', tool_calls: [{ name: 'web__echo', arguments: '{"text":"hi"}' }])
      built.agent.provider.stub_response('Echoed.')

      assert_equal 'hi', built.ask('echo hi').messages.grep(Riffer::Messages::Tool).first.content
    end

    it 'sends the declared headers' do
      built = runtime([serving(headers: { 'X-Token' => 'secret' })])

      assert_equal 'secret',
                   built.agent.tools.find { |klass|
                     klass.name == 'web__token'
                   }.new.call(context: nil).content
    end

    it 'sends the auth-resolved headers' do
      built = runtime(
        [serving(headers: { 'X-Token' => 'Bearer ${api_key}' }, auth: { api_key: 'KAGI_API_KEY' })],
        env: Riffer::Rig::Env.new({ 'KAGI_API_KEY' => 'kagi-key' }),
        auth_path: @auth_path
      )

      assert_equal 'Bearer kagi-key',
                   built.agent.tools.find { |klass|
                     klass.name == 'web__token'
                   }.new.call(context: nil).content
    end

    it 'prompts once for a missing credential and sends the answer' do
      host = Class.new(Riffer::Rig::Hosts::Null) { define_method(:ask) { |*| 'pasted' } }.new
      built = runtime(
        [serving(headers: { 'X-Token' => 'Bearer ${api_key}' }, auth: { api_key: 'KAGI_API_KEY' })],
        host: host,
        env: Riffer::Rig::Env.new({}),
        auth_path: @auth_path
      )

      assert_equal 'Bearer pasted',
                   built.agent.tools.find { |klass|
                     klass.name == 'web__token'
                   }.new.call(context: nil).content
    end

    it 'resolves the auth block of a server declared in the mcp settings' do
      settings = {
        mcp: {
          servers: {
            web: { url: @server.url, auth: { api_key: 'KAGI_API_KEY' }, headers: { 'X-Token' => 'Bearer ${api_key}' } }
          }
        }
      }
      built = runtime(
        [Riffer::Rig.bundled(:mcp)],
        settings: settings,
        env: Riffer::Rig::Env.new({ 'KAGI_API_KEY' => 'kagi-key' }),
        auth_path: @auth_path
      )

      assert_equal 'Bearer kagi-key',
                   built.agent.tools.find { |klass|
                     klass.name == 'web__token'
                   }.new.call(context: nil).content
    end

    it 'reports a server whose credential cannot be resolved through notify' do
      notice = 'MCP server web failed to register: MCP server web has no api_key (KAGI_API_KEY); ' \
               'set it in the environment or run riffer interactively to paste it'

      assert_equal [Riffer::Rig::Events::Notify.new(notice, :error)],
                   notifies(
                     runtime(
                       [serving(headers: { 'X-Token' => 'Bearer ${api_key}' }, auth: { api_key: 'KAGI_API_KEY' })],
                       env: Riffer::Rig::Env.new({}),
                       auth_path: @auth_path
                     )
                   )
    end

    it 'declares the servers in the mcp settings through the bundled extension' do
      settings = { mcp: { servers: { web: { url: @server.url } } } }

      assert_equal %w[web__echo web__token], tool_names(runtime([Riffer::Rig.bundled(:mcp)], settings: settings))
    end

    it 'tags each registration with its Runtime' do
      built = runtime([serving])

      assert_equal [:"riffer_rig_#{built.id}"], registration.manifest.tags
    end

    it "keeps one Runtime's servers from another Runtime's agent" do
      runtime([serving])

      assert_equal %w[alt__echo alt__token], tool_names(runtime([serving('alt', url: @server.url('alt'))]))
    end

    it 'reports a server with a non-HTTPS url through notify' do
      notice = 'MCP server plain failed to register: MCP manifest endpoint must be a valid HTTPS URL'

      assert_equal [Riffer::Rig::Events::Notify.new(notice, :error)],
                   notifies(runtime([serving('plain', url: 'http://127.0.0.1/mcp')]))
    end

    it 'reports a server that cannot be reached through notify' do
      notice = 'MCP server gone failed to register: Internal error handling tools/list request'

      assert_equal [Riffer::Rig::Events::Notify.new(notice, :error)],
                   notifies(runtime([serving('gone', url: 'https://127.0.0.1:1/mcp')]))
    end

    it 'reports a replaced server through notify at info level' do
      later = Riffer::Rig::Extension.new('later') { |rig| rig.mcp('web', url: @server.url) }
      notice = 'Extension later replaces MCP server web from serves_web'

      assert_equal [Riffer::Rig::Events::Notify.new(notice, :info)], notifies(runtime([serving, later]))
    end

    it 'keeps the registration across a rebuild with the same declaration' do
      built = runtime([serving])
      before = registration
      built.rebuild(extensions: [serving], settings: {})

      assert_same before, registration
    end

    it 'keeps the registration across a rebuild when the auth block resolves the same' do
      declaration = { headers: { 'X-Token' => 'Bearer ${api_key}' }, auth: { api_key: 'KAGI_API_KEY' } }
      built = runtime(
        [serving(**declaration)],
        env: Riffer::Rig::Env.new({ 'KAGI_API_KEY' => 'kagi-key' }),
        auth_path: @auth_path
      )
      before = registration
      built.rebuild(extensions: [serving(**declaration)], settings: {})

      assert_same before, registration
    end

    it 're-registers a server whose url changed on rebuild' do
      built = runtime([serving])
      before = registration
      built.rebuild(extensions: [serving(url: @server.url('alt'))], settings: {})

      refute_same before, registration
    end

    it 're-registers a server whose headers changed on rebuild' do
      built = runtime([serving])
      before = registration
      built.rebuild(extensions: [serving(headers: { 'X-Token' => 'new' })], settings: {})

      refute_same before, registration
    end

    it 'unregisters a server the rebuilt list no longer declares' do
      built = runtime([serving])
      built.rebuild(extensions: [], settings: {})

      assert_nil registration
    end

    it 'unregisters every server on close' do
      built = runtime([serving, serving('alt', url: @server.url('alt'))])
      built.close

      assert_empty Riffer::Mcp.registrations.keys & %w[web alt]
    end

    it 'leaves a server another Runtime has since registered under the same name' do
      first = runtime([serving])
      second = runtime([serving])
      first.close

      assert_equal [:"riffer_rig_#{second.id}"], registration.manifest.tags
    end
  end
end
