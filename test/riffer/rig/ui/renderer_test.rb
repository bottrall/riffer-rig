# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::UI::Renderer do
  def setup
    @io = StringIO.new
    @renderer = Riffer::Rig::UI::Renderer.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: false))
  end

  it 'writes text delta content to the io' do
    @renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))

    assert_equal 'hello', @io.string
  end

  it 'routes text deltas through the smoother when one is present' do
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))

    assert_equal ['hello'], recording_smoother.written
  end

  it 'drains the smoother before rendering a tool call done event' do
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.render(Riffer::StreamEvents::ToolCallDone.new(item_id: 'i1', call_id: 'c1', name: 'read', arguments: '{}'))

    assert_predicate recording_smoother, :drained?
  end

  it 'drains the smoother before rendering a skill activation event' do
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.render(Riffer::StreamEvents::SkillActivation.new('refactor'))

    assert_predicate recording_smoother, :drained?
  end

  it 'drains the smoother before rendering an interrupt event' do
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      smoother: recording_smoother
    )

    renderer.render(Riffer::StreamEvents::Interrupt.new(reason: 'user'))

    assert_predicate recording_smoother, :drained?
  end

  it 'drains the smoother before rendering token usage' do
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      smoother: recording_smoother,
      tally: Riffer::Rig::TokenTally.new
    )

    renderer.render(
      Riffer::StreamEvents::TokenUsageDone.new(
        token_usage: Riffer::Providers::TokenUsage.new(
          input_tokens: 1, output_tokens: 1
        )
      )
    )

    assert_predicate recording_smoother, :drained?
  end

  def recording_smoother
    @recording_smoother ||= Class.new do
      attr_reader :written

      def initialize = @written = []

      def <<(content)
        @written << content
        self
      end

      def drain = @drained = true

      def drained? = @drained == true
    end.new
  end

  it 'renders tool results without ansi when theme disabled' do
    message = Riffer::Messages::Tool.new('done', tool_call_id: 'c1', name: 'write')
    @renderer.render_tool_result(message)

    refute_includes @io.string, "\e["
  end

  it 'renders skill activation with skill name' do
    @renderer.render(Riffer::StreamEvents::SkillActivation.new('refactor'))

    assert_includes @io.string, 'skill: refactor'
  end

  it 'renders skill activation on its own line' do
    @renderer.render(Riffer::StreamEvents::SkillActivation.new('code-review'))

    assert_includes @io.string, "\n"
  end

  it 'ignores token usage done when no tally provided' do
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 50)
    event = Riffer::StreamEvents::TokenUsageDone.new(token_usage: usage)

    @renderer.render(event)

    assert_empty @io.string
  end

  it 'renders input token count when tally is present' do
    tally = Riffer::Rig::TokenTally.new
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      tally: tally
    )
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 50)
    event = Riffer::StreamEvents::TokenUsageDone.new(token_usage: usage)

    renderer.render(event)

    assert_includes @io.string, '↑100'
  end

  it 'renders output token count when tally is present' do
    tally = Riffer::Rig::TokenTally.new
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      tally: tally
    )
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 50)
    event = Riffer::StreamEvents::TokenUsageDone.new(token_usage: usage)

    renderer.render(event)

    assert_includes @io.string, '↓50'
  end

  it 'renders cache write token count when present' do
    tally = Riffer::Rig::TokenTally.new
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      tally: tally
    )
    usage = Riffer::Providers::TokenUsage.new(
      input_tokens: 100,
      output_tokens: 50,
      cache_write_tokens: 400,
      cache_read_tokens: 200
    )
    event = Riffer::StreamEvents::TokenUsageDone.new(token_usage: usage)

    renderer.render(event)

    assert_includes @io.string, 'cache_write:400'
  end

  it 'renders cache read token count when present' do
    tally = Riffer::Rig::TokenTally.new
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      tally: tally
    )
    usage = Riffer::Providers::TokenUsage.new(
      input_tokens: 100,
      output_tokens: 50,
      cache_write_tokens: 400,
      cache_read_tokens: 200
    )
    event = Riffer::StreamEvents::TokenUsageDone.new(token_usage: usage)

    renderer.render(event)

    assert_includes @io.string, 'cache_read:200'
  end

  it 'renders session token total across turns' do
    tally = Riffer::Rig::TokenTally.new
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      tally: tally
    )

    renderer.render(
      Riffer::StreamEvents::TokenUsageDone.new(
        token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 50)
      )
    )
    renderer.render(
      Riffer::StreamEvents::TokenUsageDone.new(
        token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 200, output_tokens: 100)
      )
    )

    assert_includes @io.string, 'session 450 tok'
  end

  it 'renders estimated cost for known model' do
    pricing = Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3)
    tally = Riffer::Rig::TokenTally.new(pricing: pricing)
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      tally: tally
    )
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 1000, output_tokens: 500)
    renderer.render(Riffer::StreamEvents::TokenUsageDone.new(token_usage: usage))

    assert_includes @io.string, '~$'
  end

  it 'omits estimated cost when no pricing provided' do
    tally = Riffer::Rig::TokenTally.new
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      tally: tally
    )
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 1000, output_tokens: 500)
    renderer.render(Riffer::StreamEvents::TokenUsageDone.new(token_usage: usage))

    refute_includes @io.string, '~$'
  end
end
