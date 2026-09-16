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
      max_steps: 10,
      snapshot: nil
    )

    assert_instance_of Riffer::Rig::Runtime, runtime
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
end
