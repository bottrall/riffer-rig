# frozen_string_literal: true

require 'test_helper'

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

  it 'accepts keywords whose tickets have not landed' do
    runtime = Riffer::Rig::Runtime.new(
      'mock/test',
      extensions: [@extension],
      credentials: { 'anthropic' => 'sk-ant-test' },
      pricing: { 'mock/test' => Riffer::Rig::Settings::Pricing.from({}) },
      snapshot: nil
    )

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

    assert_equal(Riffer::Rig::Events::SessionStart.new(id: runtime.id, reason: :new), first)
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

    assert_equal(Riffer::Rig::Events::TurnEnd.new(stop_reason: :completed, usage: usage), last)
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

  it 'mirrors host.notify as a notify event on the stream' do
    notifies = []
    host = Object.new
    host.define_singleton_method(:capabilities) { Set.new.freeze }
    host.define_singleton_method(:ask) { |*| nil }
    host.define_singleton_method(:confirm) { |*| false }
    host.define_singleton_method(:notify) { |message, level:| notifies << [message, level] }
    host.define_singleton_method(:progress) { |*, &block| block&.call }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], host: host)
    runtime.agent.provider.stub_response('All done.')

    notify_events = []
    runtime.host.notify('boom', level: :error)
    runtime.prompt('hello') { |event| notify_events << event if event.is_a?(Riffer::Rig::Events::Notify) }

    assert_equal [Riffer::Rig::Events::Notify.new(message: 'boom', level: :error)], notify_events
  end

  it 'passes notify through to the wrapped host' do
    notifies = []
    host = Object.new
    host.define_singleton_method(:capabilities) { Set.new.freeze }
    host.define_singleton_method(:ask) { |*| nil }
    host.define_singleton_method(:confirm) { |*| false }
    host.define_singleton_method(:notify) { |message, level:| notifies << [message, level] }
    host.define_singleton_method(:progress) { |*, &block| block&.call }
    runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [@extension], host: host)
    runtime.agent.provider.stub_response('All done.')

    runtime.host.notify('boom', level: :error)
    runtime.prompt('hello').each { |event| event }

    assert_equal [['boom', :error]], notifies
  end
end
