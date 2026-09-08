# frozen_string_literal: true

require 'test_helper'

class Riffer::Rig::SessionTest < Minitest::Test
  def setup
    @extension = Riffer::Rig.extension('test_session_tools') do |rig|
      rig.tool Riffer::Rig::Tools::Read
      rig.tool Riffer::Rig::Tools::Write
      rig.tool Riffer::Rig::Tools::Edit
      rig.tool Riffer::Rig::Tools::Bash
    end
  end

  def teardown
    Riffer::Rig.instance_variable_get(:@extensions).delete('test_session_tools')
  end

  def test_prompt_yields_riffer_stream_events
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    session.agent.provider.stub_response('All done.')
    events = []
    session.prompt('hello') { |event| events << event }

    assert(events.any?(Riffer::StreamEvents::TextDone))
  end

  def test_prompt_without_a_block_returns_an_enumerator
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    session.agent.provider.stub_response('All done.')

    assert_instance_of Enumerator, session.prompt('hello')
  end

  def test_an_extension_registers_the_bundled_tool_classes
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Write, Riffer::Rig::Tools::Edit, Riffer::Rig::Tools::Bash], session.agent.tools
  end

  def test_two_sessions_do_not_share_tools
    other = Riffer::Rig.extension('test_session_other') { |rig| rig.tool Riffer::Rig::Tools::Read }
    Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    two = Riffer::Rig::Session.new('mock/test', extensions: [other])

    assert_equal [Riffer::Rig::Tools::Read], two.agent.tools
  end

  def test_the_process_registry_stays_shared_between_sessions
    other = Riffer::Rig.extension('test_session_other') { |rig| rig.tool Riffer::Rig::Tools::Read }
    one = Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    Riffer::Rig::Session.new('mock/test', extensions: [other])

    assert_equal 4, one.agent.tools.length
  end

  def test_tools_allowlist_filters_by_identifier
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension], tools: %w[read bash])

    assert_equal [Riffer::Rig::Tools::Read, Riffer::Rig::Tools::Bash], session.agent.tools
  end

  def test_the_base_prompt_names_the_agent
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])

    assert_includes session.agent.instruction_message.content, 'You are riffer, a general-purpose agent.'
  end

  def test_the_base_prompt_states_the_norms
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])

    assert_includes session.agent.instruction_message.content, 'Be concise. Lead with the outcome'
  end

  def test_the_environment_block_carries_the_date_and_cwd
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension], cwd: '/tmp/proj')

    assert_includes session.agent.instruction_message.content, "Current date: #{Date.today}\nCurrent working directory: /tmp/proj"
  end

  def test_the_base_prompt_lists_no_tools
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])

    refute_includes session.agent.instruction_message.content, 'read:'
  end

  def test_name_swaps_the_name_inside_the_base_prompt
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension], name: 'sidekick')

    assert_includes session.agent.instruction_message.content, 'You are sidekick, a general-purpose agent.'
  end

  def test_instructions_replace_the_base_prompt
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension], instructions: 'CUSTOM_BASE')

    assert_includes session.agent.instruction_message.content, 'CUSTOM_BASE'
  end

  def test_instructions_keep_the_environment_block
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension], instructions: 'CUSTOM_BASE', cwd: '/tmp/proj')

    assert_includes session.agent.instruction_message.content, "Current date: #{Date.today}\nCurrent working directory: /tmp/proj"
  end

  def test_instructions_drop_the_default_base
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension], instructions: 'CUSTOM_BASE')

    refute_includes session.agent.instruction_message.content, 'general-purpose agent'
  end

  def test_a_second_prompt_while_one_runs_raises
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    session.agent.provider.stub_response('first')

    session.prompt('hello') do
      assert_raises(Riffer::Rig::Session::BusyError) { session.prompt('second').each { |event| event } }
      break
    end
  end

  def test_prompt_is_usable_again_after_a_turn_ends
    session = Riffer::Rig::Session.new('mock/test', extensions: [@extension])
    session.agent.provider.stub_response('first')
    session.agent.provider.stub_response('second')
    session.prompt('hello').each { |event| event }

    assert_equal 'second', session.prompt('hello').find { |event| event.is_a?(Riffer::StreamEvents::TextDone) }.content
  end
end
