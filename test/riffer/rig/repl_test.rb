# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class Riffer::Rig::REPLTest < Minitest::Test
  def test_run_exits_on_empty_input_and_prints_the_sign_off
    output = StringIO.new
    theme = Riffer::Rig::UI::Theme.new(enabled: false)
    renderer = Riffer::Rig::UI::Renderer.new(io: output, theme: theme)
    repl = Riffer::Rig::REPL.new(agent: Riffer::Rig::CodingAgent.new, renderer: renderer, input: StringIO.new(''), output: output, theme: theme)

    repl.run

    assert_includes output.string, 'next riff'
  end

  def test_skill_command_activates_skill_and_prints_confirmation
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      assert_includes output.string, 'skill: refactor'
    end
  end

  def test_skill_command_marks_skill_as_activated_on_agent
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      assert agent.context.skills.activated?('refactor')
    end
  end

  def test_skill_command_injects_skill_body_as_a_user_turn
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      assert(agent.session.messages.any? { |m| m.role == :user && m.content.include?('You are the refactor assistant.') })
    end
  end

  def test_skill_command_wraps_the_body_in_a_skill_block
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      assert(agent.session.messages.any? { |m| m.role == :user && m.content.include?('<skill name="refactor">') })
    end
  end

  def test_repeated_skill_invocation_re_injects_the_body
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n/skill:refactor\n")

      repl.run

      bodies = agent.session.messages.count { |m| m.role == :user && m.content.include?('You are the refactor assistant.') }

      assert_equal 2, bodies
    end
  end

  def test_skill_command_with_trailing_text_combines_block_and_text
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor clean up foo.rb\n")

      repl.run

      assert(agent.session.messages.any? do |m|
        m.role == :user && m.content.include?('<skill name="refactor">') && m.content.include?('clean up foo.rb')
      end)
    end
  end

  def test_skill_only_prompt_does_not_send_an_empty_user_turn
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      refute(agent.session.messages.any? { |m| m.role == :user && m.content.strip.empty? })
    end
  end

  def test_skill_only_prompt_triggers_agent_turn
    with_skill('refactor') do |_agent, output|
      agent = mock_agent
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      # The mock provider returns "Mock response" — confirms agent.stream was called
      assert_includes output.string, 'Mock response'
    end
  end

  def test_unknown_skill_command_reports_the_error
    with_skill('refactor') do |_agent, output|
      agent = mock_agent
      repl = build_repl(agent, output, "/skill:nonexistent\n")

      repl.run

      assert_includes output.string, 'Unknown skill: nonexistent'
    end
  end

  def test_unknown_skill_command_does_not_trigger_agent_turn
    with_skill('refactor') do |_agent, output|
      agent = mock_agent
      repl = build_repl(agent, output, "/skill:nonexistent\n")

      repl.run

      refute_includes output.string, 'Mock response'
    end
  end

  def test_skill_token_without_prefix_is_a_plain_prompt
    with_skill('refactor') do |_agent, output|
      agent = mock_agent
      repl = build_repl(agent, output, "/refactor please clean up this file\n")

      repl.run

      refute_includes output.string, 'skill: refactor'
    end
  end

  def test_skill_command_must_anchor_to_start_of_line
    with_skill('refactor') do |_agent, output|
      agent = mock_agent
      repl = build_repl(agent, output, "please /skill:refactor this file\n")

      repl.run

      refute_includes output.string, 'skill: refactor'
    end
  end

  def test_exit_command_exits_the_repl
    output = StringIO.new
    repl = build_repl(Riffer::Rig::CodingAgent.new, output, "/exit\n")

    repl.run

    assert_includes output.string, 'next riff'
  end

  def test_exit_command_is_not_treated_as_skill_command
    output = StringIO.new
    repl = build_repl(Riffer::Rig::CodingAgent.new, output, "/exit\n")

    repl.run

    refute_includes output.string, 'skill:'
  end

  def test_reasoning_events_keep_the_indicator_running
    animator = spy_animator
    agent = stub_agent([Riffer::StreamEvents::ReasoningDelta.new('hmm'), Riffer::StreamEvents::ReasoningDone.new('hmm')])
    repl = build_repl(agent, StringIO.new, "hi\n", animator: animator)

    repl.run

    assert_equal [%i[start neutral], %i[start reasoning], %i[start neutral], :stop, :stop], animator.calls
  end

  def test_renderable_events_stop_the_indicator
    animator = spy_animator
    agent = stub_agent([Riffer::StreamEvents::TextDelta.new('hello')])
    repl = build_repl(agent, StringIO.new, "hi\n", animator: animator)

    repl.run

    assert_equal [%i[start neutral], :stop, :stop, :stop], animator.calls
  end

  def test_indicator_restarts_after_a_tool_call_completes
    animator = spy_animator
    agent = stub_agent([
                         Riffer::StreamEvents::ToolCallDelta.new(item_id: 'i1', arguments_delta: '{"f'),
                         Riffer::StreamEvents::ToolCallDone.new(item_id: 'i1', call_id: 'c1', name: 'read', arguments: '{}'),
                         Riffer::StreamEvents::FinishReasonDone.new(finish_reason: :tool_calls),
                         Riffer::StreamEvents::TokenUsageDone.new(token_usage: build_token_usage)
                       ])
    repl = build_repl(agent, StringIO.new, "hi\n", animator: animator)

    repl.run

    assert_equal [%i[start neutral], :stop, %i[start neutral], :stop, %i[start neutral], :stop, :stop], animator.calls
  end

  def test_indicator_restarts_after_a_skill_activates
    animator = spy_animator
    agent = stub_agent([Riffer::StreamEvents::SkillActivation.new('read')])
    repl = build_repl(agent, StringIO.new, "hi\n", animator: animator)

    repl.run

    assert_equal [%i[start neutral], :stop, %i[start neutral], :stop, :stop], animator.calls
  end

  def test_indicator_survives_tool_call_deltas_and_finish_reason
    animator = spy_animator
    agent = stub_agent([
                         Riffer::StreamEvents::ToolCallDelta.new(item_id: 'i1', arguments_delta: '{"f'),
                         Riffer::StreamEvents::FinishReasonDone.new(finish_reason: :tool_calls)
                       ])
    repl = build_repl(agent, StringIO.new, "hi\n", animator: animator)

    repl.run

    assert_equal [%i[start neutral], :stop, :stop], animator.calls
  end

  def test_reasoning_resuming_mid_turn_restarts_the_indicator
    animator = spy_animator
    agent = stub_agent([Riffer::StreamEvents::TextDelta.new('hello'), Riffer::StreamEvents::ReasoningDelta.new('hmm')])
    repl = build_repl(agent, StringIO.new, "hi\n", animator: animator)

    repl.run

    assert_equal [%i[start neutral], :stop, %i[start reasoning], :stop, :stop], animator.calls
  end

  def test_indicator_is_stopped_before_the_end_of_turn_newline
    animator = spy_animator
    order = animator.calls
    output = StringIO.new
    output.define_singleton_method(:puts) { |str = ''| order << [:write, str] }
    agent = stub_agent([Riffer::StreamEvents::ToolCallDone.new(item_id: 'i1', call_id: 'c1', name: 'read', arguments: '{}')])
    repl = build_repl(agent, output, "hi\n", animator: animator)

    repl.run

    last_start = order.rindex { |call| call.is_a?(Array) && call.first == :start }
    following_stop = order[(last_start + 1)..].index(:stop) + last_start + 1
    epilogue = order.rindex { |call| call.is_a?(Array) && call.first == :write && call.last.empty? }

    assert_operator following_stop, :<, epilogue
  end

  def test_tool_result_printing_stops_and_restarts_the_indicator
    animator = spy_animator
    tool_message = Riffer::Messages::Tool.new('ok', tool_call_id: 'c1', name: 'read')
    order = []
    animator.define_singleton_method(:stop) { order << :stop }
    animator.define_singleton_method(:start) { |mode = :neutral| order << [:start, mode] }
    renderer = Object.new
    renderer.define_singleton_method(:render_tool_result) { |m| order << [:render, m] }

    repl = build_repl(stub_agent([]), StringIO.new, '', animator: animator)
    repl.instance_variable_set(:@renderer, renderer)
    repl.send(:render_tool_result, tool_message)

    assert_equal [:stop, [:render, tool_message], %i[start neutral]], order
  end

  private

  def build_token_usage
    Riffer::Providers::TokenUsage.new(input_tokens: 1, output_tokens: 1)
  end

  def mock_agent
    config = Riffer::Rig::CodingAgent.config.dup
    config.model = 'mock/claude-test'
    Riffer::Rig::CodingAgent.new(config: config)
  end

  def spy_animator
    animator = Object.new
    def animator.calls = @calls ||= []
    def animator.start(mode = :neutral) = calls << [:start, mode]
    def animator.stop = calls << :stop
    animator
  end

  def stub_agent(events)
    agent = Object.new
    stream_result = events.each
    agent.define_singleton_method(:stream) { |_prompt| stream_result }
    session = Object.new
    session.define_singleton_method(:on_message) { |*_args| nil }
    agent.define_singleton_method(:session) { session }
    context = Object.new
    context.define_singleton_method(:skills) { nil }
    agent.define_singleton_method(:context) { context }
    agent
  end

  def build_repl(agent, output, input_str, animator: Riffer::Rig::UI::Animator.new(io: output, theme: Riffer::Rig::UI::Theme.new(enabled: false)))
    theme = Riffer::Rig::UI::Theme.new(enabled: false)
    renderer = Riffer::Rig::UI::Renderer.new(io: output, theme: theme)
    Riffer::Rig::REPL.new(agent: agent, renderer: renderer, input: StringIO.new(input_str), output: output, theme: theme, animator: animator)
  end

  def with_skill(name, &)
    with_skills(name, &)
  end

  def with_skills(*names)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        names.each do |name|
          skill_dir = File.join(dir, '.skills', name)
          FileUtils.mkdir_p(skill_dir)
          File.write(File.join(skill_dir, 'SKILL.md'), <<~MD)
            ---
            name: #{name}
            description: A test skill named #{name}.
            ---
            You are the #{name} assistant.
          MD
        end

        output = StringIO.new
        agent = Riffer::Rig::CodingAgent.new
        yield(agent, output)
      end
    end
  end
end
