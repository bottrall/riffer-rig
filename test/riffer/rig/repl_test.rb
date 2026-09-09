# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::REPL do
  it 'run exits on empty input and prints the sign off' do
    output = StringIO.new
    theme = Riffer::Rig::UI::Theme.new(enabled: false)
    renderer = Riffer::Rig::UI::Renderer.new(io: output, theme: theme)
    repl = Riffer::Rig::REPL.new(agent: Riffer::Rig::CodingAgent.new, renderer: renderer, input: StringIO.new(''), output: output, theme: theme)

    repl.run

    assert_includes output.string, 'next riff'
  end

  it 'skill command activates skill and prints confirmation' do
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      assert_includes output.string, 'skill: refactor'
    end
  end

  it 'skill command marks skill as activated on agent' do
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      assert agent.context.skills.activated?('refactor')
    end
  end

  it 'skill command injects skill body as a user turn' do
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      assert(agent.session.messages.any? { |m| m.role == :user && m.content.include?('You are the refactor assistant.') })
    end
  end

  it 'skill command wraps the body in a skill block' do
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      assert(agent.session.messages.any? { |m| m.role == :user && m.content.include?('<skill name="refactor">') })
    end
  end

  it 'repeated skill invocation re injects the body' do
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n/skill:refactor\n")

      repl.run

      bodies = agent.session.messages.count { |m| m.role == :user && m.content.include?('You are the refactor assistant.') }

      assert_equal 2, bodies
    end
  end

  it 'skill command with trailing text combines block and text' do
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor clean up foo.rb\n")

      repl.run

      assert(agent.session.messages.any? do |m|
        m.role == :user && m.content.include?('<skill name="refactor">') && m.content.include?('clean up foo.rb')
      end)
    end
  end

  it 'skill only prompt does not send an empty user turn' do
    with_skill('refactor') do |agent, output|
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      refute(agent.session.messages.any? { |m| m.role == :user && m.content.strip.empty? })
    end
  end

  it 'skill only prompt triggers agent turn' do
    with_skill('refactor') do |_agent, output|
      agent = mock_agent
      repl = build_repl(agent, output, "/skill:refactor\n")

      repl.run

      # The mock provider returns "Mock response" — confirms agent.stream was called
      assert_includes output.string, 'Mock response'
    end
  end

  it 'unknown skill command reports the error' do
    with_skill('refactor') do |_agent, output|
      agent = mock_agent
      repl = build_repl(agent, output, "/skill:nonexistent\n")

      repl.run

      assert_includes output.string, 'Unknown skill: nonexistent'
    end
  end

  it 'unknown skill command does not trigger agent turn' do
    with_skill('refactor') do |_agent, output|
      agent = mock_agent
      repl = build_repl(agent, output, "/skill:nonexistent\n")

      repl.run

      refute_includes output.string, 'Mock response'
    end
  end

  it 'skill token without prefix is a plain prompt' do
    with_skill('refactor') do |_agent, output|
      agent = mock_agent
      repl = build_repl(agent, output, "/refactor please clean up this file\n")

      repl.run

      refute_includes output.string, 'skill: refactor'
    end
  end

  it 'skill command must anchor to start of line' do
    with_skill('refactor') do |_agent, output|
      agent = mock_agent
      repl = build_repl(agent, output, "please /skill:refactor this file\n")

      repl.run

      refute_includes output.string, 'skill: refactor'
    end
  end

  it 'exit command exits the repl' do
    output = StringIO.new
    repl = build_repl(Riffer::Rig::CodingAgent.new, output, "/exit\n")

    repl.run

    assert_includes output.string, 'next riff'
  end

  it 'exit command is not treated as skill command' do
    output = StringIO.new
    repl = build_repl(Riffer::Rig::CodingAgent.new, output, "/exit\n")

    repl.run

    refute_includes output.string, 'skill:'
  end

  it 'reasoning events keep the indicator running' do
    animator = spy_animator
    agent = stub_agent([Riffer::StreamEvents::ReasoningDelta.new('hmm'), Riffer::StreamEvents::ReasoningDone.new('hmm')])
    repl = build_repl(agent, StringIO.new, "hi\n", animator: animator)

    repl.run

    assert_equal [%i[start neutral], %i[start reasoning], %i[start neutral], :stop, :stop], animator.calls
  end

  it 'renderable events stop the indicator' do
    animator = spy_animator
    agent = stub_agent([Riffer::StreamEvents::TextDelta.new('hello')])
    repl = build_repl(agent, StringIO.new, "hi\n", animator: animator)

    repl.run

    assert_equal [%i[start neutral], :stop, :stop, :stop], animator.calls
  end

  it 'indicator restarts after a tool call completes' do
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

  it 'indicator restarts after a skill activates' do
    animator = spy_animator
    agent = stub_agent([Riffer::StreamEvents::SkillActivation.new('read')])
    repl = build_repl(agent, StringIO.new, "hi\n", animator: animator)

    repl.run

    assert_equal [%i[start neutral], :stop, %i[start neutral], :stop, :stop], animator.calls
  end

  it 'indicator survives tool call deltas and finish reason' do
    animator = spy_animator
    agent = stub_agent([
                         Riffer::StreamEvents::ToolCallDelta.new(item_id: 'i1', arguments_delta: '{"f'),
                         Riffer::StreamEvents::FinishReasonDone.new(finish_reason: :tool_calls)
                       ])
    repl = build_repl(agent, StringIO.new, "hi\n", animator: animator)

    repl.run

    assert_equal [%i[start neutral], :stop, :stop], animator.calls
  end

  it 'reasoning resuming mid turn restarts the indicator' do
    animator = spy_animator
    agent = stub_agent([Riffer::StreamEvents::TextDelta.new('hello'), Riffer::StreamEvents::ReasoningDelta.new('hmm')])
    repl = build_repl(agent, StringIO.new, "hi\n", animator: animator)

    repl.run

    assert_equal [%i[start neutral], :stop, %i[start reasoning], :stop, :stop], animator.calls
  end

  it 'indicator is stopped before the end of turn newline' do
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

  it 'tool result printing stops and restarts the indicator' do
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

  it 'cursor is shown after all turn output' do
    cursor = spy_cursor
    output = StringIO.new
    order = cursor.calls
    output.define_singleton_method(:puts) { |str = ''| order << [:write, str] }
    repl = build_repl(stub_agent([]), output, "hi\n", cursor: cursor)

    repl.run

    epilogue = order.rindex { |call| call.is_a?(Array) && call.first == :write && call.last.empty? }

    assert_operator order.rindex(:show), :>, epilogue
  end

  it 'cursor is shown when the turn raises' do
    cursor = spy_cursor
    agent = stub_agent([Riffer::StreamEvents::TextDelta.new('hello')])
    agent.define_singleton_method(:stream) { |_prompt| raise 'boom' }

    repl = build_repl(agent, StringIO.new, "hi\n", cursor: cursor)

    repl.run

    assert_equal %i[hide show], cursor.calls
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

  def spy_cursor
    cursor = Object.new
    def cursor.calls = @calls ||= []
    def cursor.hide = calls << :hide
    def cursor.show = calls << :show
    cursor
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

  def build_repl(agent, output, input_str, animator: Riffer::Rig::UI::Animator.new(io: output, theme: Riffer::Rig::UI::Theme.new(enabled: false)), cursor: Riffer::Rig::UI::Cursor.new(io: output, theme: Riffer::Rig::UI::Theme.new(enabled: false)))
    theme = Riffer::Rig::UI::Theme.new(enabled: false)
    renderer = Riffer::Rig::UI::Renderer.new(io: output, theme: theme)
    Riffer::Rig::REPL.new(agent: agent, renderer: renderer, input: StringIO.new(input_str), output: output, theme: theme, animator: animator, cursor: cursor)
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
