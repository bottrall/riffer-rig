# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::UI::Animator do
  def setup
    @io = StringIO.new
    @animator = Riffer::Rig::UI::Animator.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: false))
  end

  it 'reveal prints the final frame when not a tty' do
    @animator.reveal([['frame one'], ['final']])

    assert_equal "final\n", @io.string
  end

  it 'stop without start does not raise' do
    @animator.stop

    assert_equal '', @io.string
  end

  it 'start is a no op when not a tty' do
    @animator.start

    assert_equal '', @io.string
  end

  it 'start reasoning is a no op when not a tty' do
    @animator.start(:reasoning)

    assert_equal '', @io.string
  end

  it 'thinking frames render the equalizer when enabled' do
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    animator = Riffer::Rig::UI::Animator.new(io: io, theme: Riffer::Rig::UI::Theme.new(enabled: true))
    animator.start
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until io.string.include?('riffing') || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    animator.stop

    assert_includes io.string, 'riffing'
  end

  it 'equalizer has no escapes when theme disabled' do
    animator = Riffer::Rig::UI::Animator.new(io: StringIO.new, theme: Riffer::Rig::UI::Theme.new(enabled: false))
    frame = animator.equalizer(3)

    refute_includes frame, "\e["
  end

  it 'equalizer renders the neutral label by default' do
    animator = Riffer::Rig::UI::Animator.new(io: StringIO.new, theme: Riffer::Rig::UI::Theme.new(enabled: false))
    frame = animator.equalizer(3)

    assert_includes frame, 'riffing…'
  end

  it 'equalizer renders the given label' do
    animator = Riffer::Rig::UI::Animator.new(io: StringIO.new, theme: Riffer::Rig::UI::Theme.new(enabled: false))
    frame = animator.equalizer(3, 'pondering…')

    assert_includes frame, 'pondering…'
  end

  it 'thinking frames render reasoning phrases when started in reasoning mode' do
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    animator = Riffer::Rig::UI::Animator.new(io: io, theme: Riffer::Rig::UI::Theme.new(enabled: true))
    animator.start(:reasoning)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    Process.clock_gettime(Process::CLOCK_MONOTONIC) until Riffer::Rig::UI::Animator::REASONING_PHRASES.any? do |phrase|
      io.string.include?(phrase)
    end || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    animator.stop

    assert(Riffer::Rig::UI::Animator::REASONING_PHRASES.any? { |phrase| io.string.include?(phrase) })
  end

  it 'relabeling to reasoning does not restart a running thread' do
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    animator = Riffer::Rig::UI::Animator.new(io: io, theme: Riffer::Rig::UI::Theme.new(enabled: true))
    animator.start
    animator.start(:reasoning)
    animator.start
    animator.stop

    assert_nil animator.instance_variable_get(:@thread)
  end
end
