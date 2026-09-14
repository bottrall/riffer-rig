# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Session do
  before do
    @extension = Riffer::Rig.extension('test_session_tools') do |rig|
      rig.tool Riffer::Rig::Tools::Read
      rig.tool Riffer::Rig::Tools::Write
      rig.tool Riffer::Rig::Tools::Edit
      rig.tool Riffer::Rig::Tools::Bash
    end
  end

  after do
    Riffer::Rig.instance_variable_get(:@extensions).delete('test_session_tools')
  end

  it 'prompts with a block, yielding riffer stream events' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    session.agent.provider.stub_response('All done.')
    events = []
    session.prompt('hello') { |event| events << event }

    assert(events.any?(Riffer::StreamEvents::TextDone))
  end

  it 'prompts without a block, returning an enumerator' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    session.agent.provider.stub_response('All done.')

    assert_instance_of Enumerator, session.prompt('hello')
  end

  it 'registers the bundled tool classes through an extension' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Write, Riffer::Rig::Tools::Edit, Riffer::Rig::Tools::Bash],
                 session.agent.tools
  end

  it 'gives a second session its own tools' do
    other = Riffer::Rig.extension('test_session_other') { |rig| rig.tool Riffer::Rig::Tools::Read }
    Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    two = Riffer::Rig::Session.new('mock/test', extensions: [other])

    assert_equal [Riffer::Rig::Tools::Read], two.agent.tools
  end

  it 'keeps the process registry shared between sessions' do
    other = Riffer::Rig.extension('test_session_other') { |rig| rig.tool Riffer::Rig::Tools::Read }
    one = Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    Riffer::Rig::Session.new('mock/test', extensions: [other])

    assert_equal 4, one.agent.tools.length
  end

  it 'filters the registered tools by the allowlist' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension], tools: %w[read bash])

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Bash], session.agent.tools
  end

  it 'accepts keywords whose tickets have not landed' do
    session = Riffer::Rig::Session.new(
      'mock/test',
      extensions: [@extension],
      credentials: { anthropic: {} },
      pricing: {},
      max_steps: 10,
      snapshot: nil
    )

    assert_instance_of Riffer::Rig::Session, session
  end

  it 'names the agent in the base prompt' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])

    assert_includes session.agent.instruction_message.content, 'You are riffer, a general-purpose agent.'
  end

  it 'states the norms in the base prompt' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])

    assert_includes session.agent.instruction_message.content, 'Be concise. Lead with the outcome'
  end

  it 'carries the date and cwd in the environment block' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension], cwd: '/tmp/proj')

    assert_includes session.agent.instruction_message.content,
                    "Current date: #{Date.today}\nCurrent working directory: /tmp/proj"
  end

  it 'lists no tools in the base prompt' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])

    refute_includes session.agent.instruction_message.content, 'read:'
  end

  it 'swaps the name inside the base prompt' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension], name: 'sidekick')

    assert_includes session.agent.instruction_message.content, 'You are sidekick, a general-purpose agent.'
  end

  it 'replaces the base prompt with instructions' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension], instructions: 'CUSTOM_BASE')

    assert_includes session.agent.instruction_message.content, 'CUSTOM_BASE'
  end

  it 'keeps the environment block under custom instructions' do
    session = Riffer::Rig::Session.new(
      'mock/test',
      extensions: [@extension],
      instructions: 'CUSTOM_BASE',
      cwd: '/tmp/proj'
    )

    assert_includes session.agent.instruction_message.content,
                    "Current date: #{Date.today}\nCurrent working directory: /tmp/proj"
  end

  it 'drops the default base under custom instructions' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension], instructions: 'CUSTOM_BASE')

    refute_includes session.agent.instruction_message.content, 'general-purpose agent'
  end

  it 'raises on a second prompt while one runs' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    session.agent.provider.stub_response('first')

    assert_raises(Riffer::Rig::Session::BusyError) do
      session.prompt('hello') do
        session.prompt('second').each { |event| event }
      end
    end
  end

  it 'is usable again after a turn ends' do
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    session.agent.provider.stub_response('first')
    session.agent.provider.stub_response('second')
    session.prompt('hello').each { |event| event }

    assert_equal 'second', session.prompt('hello').find { |event| event.is_a?(Riffer::StreamEvents::TextDone) }.content
  end
end
