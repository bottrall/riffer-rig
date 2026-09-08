# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class Riffer::Rig::UI::AnimatorTest < Minitest::Test
  def setup
    @io = StringIO.new
    @animator = Riffer::Rig::UI::Animator.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: false))
  end

  def test_reveal_prints_the_final_frame_when_not_a_tty
    @animator.reveal([['frame one'], ['final']])

    assert_equal "final\n", @io.string
  end

  def test_stop_thinking_without_start_does_not_raise
    @animator.stop_thinking

    assert_equal '', @io.string
  end

  def test_start_thinking_is_a_no_op_when_not_a_tty
    @animator.start_thinking

    assert_equal '', @io.string
  end

  def test_start_reasoning_is_a_no_op_when_not_a_tty
    @animator.start_reasoning

    assert_equal '', @io.string
  end

  def test_thinking_frames_render_the_equalizer_when_enabled
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    animator = Riffer::Rig::UI::Animator.new(io: io, theme: Riffer::Rig::UI::Theme.new(enabled: true))
    animator.start_thinking
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    Process.clock_gettime(Process::CLOCK_MONOTONIC) until io.string.include?('riffing') || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    animator.stop_thinking

    assert_includes io.string, 'riffing'
  end

  def test_equalizer_has_no_escapes_when_theme_disabled
    animator = Riffer::Rig::UI::Animator.new(io: StringIO.new, theme: Riffer::Rig::UI::Theme.new(enabled: false))
    frame = animator.equalizer(3)

    refute_includes frame, "\e["
  end

  def test_equalizer_renders_the_neutral_label_by_default
    animator = Riffer::Rig::UI::Animator.new(io: StringIO.new, theme: Riffer::Rig::UI::Theme.new(enabled: false))
    frame = animator.equalizer(3)

    assert_includes frame, 'riffing…'
  end

  def test_equalizer_renders_the_given_label
    animator = Riffer::Rig::UI::Animator.new(io: StringIO.new, theme: Riffer::Rig::UI::Theme.new(enabled: false))
    frame = animator.equalizer(3, 'pondering…')

    assert_includes frame, 'pondering…'
  end

  def test_thinking_frames_render_reasoning_phrases_when_started_in_reasoning_mode
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    animator = Riffer::Rig::UI::Animator.new(io: io, theme: Riffer::Rig::UI::Theme.new(enabled: true))
    animator.start_reasoning
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    Process.clock_gettime(Process::CLOCK_MONOTONIC) until Riffer::Rig::UI::Animator::REASONING_PHRASES.any? { |phrase| io.string.include?(phrase) } || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    animator.stop_thinking

    assert(Riffer::Rig::UI::Animator::REASONING_PHRASES.any? { |phrase| io.string.include?(phrase) })
  end

  def test_relabeling_to_reasoning_does_not_restart_a_running_thread
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    animator = Riffer::Rig::UI::Animator.new(io: io, theme: Riffer::Rig::UI::Theme.new(enabled: true))
    animator.start_thinking
    animator.start_reasoning
    animator.start_thinking
    animator.stop_thinking

    assert_nil animator.instance_variable_get(:@thread)
  end
end
