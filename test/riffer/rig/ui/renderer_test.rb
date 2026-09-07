# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class Riffer::Rig::UI::RendererTest < Minitest::Test
  def setup
    @io = StringIO.new
    @renderer = Riffer::Rig::UI::Renderer.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: false))
  end

  def test_writes_text_delta_content_to_the_io
    @renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))

    assert_equal 'hello', @io.string
  end

  def test_routes_text_deltas_through_the_smoother_when_one_is_present
    renderer = Riffer::Rig::UI::Renderer.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: false), smoother: recording_smoother)

    renderer.render(Riffer::StreamEvents::TextDelta.new('hello'))

    assert_equal ['hello'], recording_smoother.written
  end

  def test_drains_the_smoother_before_rendering_a_tool_call_done_event
    renderer = Riffer::Rig::UI::Renderer.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: false), smoother: recording_smoother)

    renderer.render(Riffer::StreamEvents::ToolCallDone.new(item_id: 'i1', call_id: 'c1', name: 'read', arguments: '{}'))

    assert_predicate recording_smoother, :drained?
  end

  def test_drains_the_smoother_before_rendering_a_skill_activation_event
    renderer = Riffer::Rig::UI::Renderer.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: false), smoother: recording_smoother)

    renderer.render(Riffer::StreamEvents::SkillActivation.new('refactor'))

    assert_predicate recording_smoother, :drained?
  end

  def test_drains_the_smoother_before_rendering_an_interrupt_event
    renderer = Riffer::Rig::UI::Renderer.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: false), smoother: recording_smoother)

    renderer.render(Riffer::StreamEvents::Interrupt.new(reason: 'user'))

    assert_predicate recording_smoother, :drained?
  end

  def test_drains_the_smoother_before_rendering_token_usage
    renderer = Riffer::Rig::UI::Renderer.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: false), smoother: recording_smoother, tally: Riffer::Rig::TokenTally.new)

    renderer.render(Riffer::StreamEvents::TokenUsageDone.new(token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 1, output_tokens: 1)))

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

  def test_renders_tool_results_without_ansi_when_theme_disabled
    message = Riffer::Messages::Tool.new('done', tool_call_id: 'c1', name: 'write')
    @renderer.render_tool_result(message)

    refute_includes @io.string, "\e["
  end

  def test_renders_skill_activation_with_skill_name
    @renderer.render(Riffer::StreamEvents::SkillActivation.new('refactor'))

    assert_includes @io.string, 'skill: refactor'
  end

  def test_renders_skill_activation_on_its_own_line
    @renderer.render(Riffer::StreamEvents::SkillActivation.new('code-review'))

    assert_includes @io.string, "\n"
  end

  def test_ignores_token_usage_done_when_no_tally_provided
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 50)
    event = Riffer::StreamEvents::TokenUsageDone.new(token_usage: usage)

    @renderer.render(event)

    assert_empty @io.string
  end

  def test_renders_input_token_count_when_tally_is_present
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

  def test_renders_output_token_count_when_tally_is_present
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

  def test_renders_cache_write_token_count_when_present
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

  def test_renders_cache_read_token_count_when_present
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

  def test_renders_session_token_total_across_turns
    tally = Riffer::Rig::TokenTally.new
    renderer = Riffer::Rig::UI::Renderer.new(
      io: @io,
      theme: Riffer::Rig::UI::Theme.new(enabled: false),
      tally: tally
    )

    renderer.render(Riffer::StreamEvents::TokenUsageDone.new(
                      token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 50)
                    ))
    renderer.render(Riffer::StreamEvents::TokenUsageDone.new(
                      token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 200, output_tokens: 100)
                    ))

    assert_includes @io.string, 'session 450 tok'
  end

  def test_renders_estimated_cost_for_known_model
    pricing = { input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3 }
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

  def test_omits_estimated_cost_when_no_pricing_provided
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
