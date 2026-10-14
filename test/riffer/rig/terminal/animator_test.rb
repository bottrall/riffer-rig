# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Terminal::Animator do
  def setup
    @io = StringIO.new
    @animator = Riffer::Rig::Terminal::Animator.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
  end

  def tty_io
    StringIO.new.tap { |io| io.define_singleton_method(:tty?) { true } }
  end

  def await(seconds = 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    Thread.pass until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  it 'reveal prints the final frame when not a tty' do
    @animator.reveal([['frame one'], ['final']])

    assert_equal "final\n", @io.string
  end

  it 'reveal prints only the final frame when the theme is disabled on a tty' do
    io = tty_io
    animator = Riffer::Rig::Terminal::Animator.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
    animator.reveal([['frame one'], ['final']])

    assert_equal "final\n", io.string
  end

  it 'reveal prints only the final frame when the theme is enabled off a tty' do
    animator = Riffer::Rig::Terminal::Animator.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.reveal([['frame one'], ['final']])

    assert_equal "final\n", @io.string
  end

  it 'reveal redraws each frame over the last and leaves the final one in place' do
    io = tty_io
    animator = Riffer::Rig::Terminal::Animator.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.reveal([%w[a b], %w[c d]])

    assert_equal "a\e[K\nb\e[K\n\e[2A\rc\e[K\nd\e[K\n", io.string
  end

  it 'start is a no op when not a tty' do
    @animator.start

    assert_equal '', @io.string
  end

  it 'start reasoning is a no op when not a tty' do
    @animator.start(:reasoning)

    assert_equal '', @io.string
  end

  it 'relabeling to reasoning does not restart a running thread' do
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    animator = Riffer::Rig::Terminal::Animator.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.start
    animator.start(:reasoning)
    animator.start
    animator.stop

    assert_nil animator.instance_variable_get(:@thread)
  end

  it 'start while running does not spawn a second thread' do
    animator = Riffer::Rig::Terminal::Animator.new(io: tty_io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.start
    running = Thread.list
    animator.start(:reasoning)
    spawned = Thread.list - running
    animator.stop

    assert_empty spawned
  end

  it 'stop without start does not raise' do
    @animator.stop

    assert_equal '', @io.string
  end

  it 'stop clears the spinner line' do
    io = tty_io
    animator = Riffer::Rig::Terminal::Animator.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.start
    await { io.string.include?('riffing') }
    animator.stop

    assert io.string.end_with?("\r\e[K")
  end

  it 'equalizer has no escapes when theme disabled' do
    animator = Riffer::Rig::Terminal::Animator.new(
      io: StringIO.new,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false)
    )
    frame = animator.equalizer(3)

    refute_includes frame, "\e["
  end

  it 'equalizer renders the neutral label by default' do
    animator = Riffer::Rig::Terminal::Animator.new(
      io: StringIO.new,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false)
    )
    frame = animator.equalizer(3)

    assert_includes frame, 'riffing…'
  end

  it 'equalizer renders the given label' do
    animator = Riffer::Rig::Terminal::Animator.new(
      io: StringIO.new,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false)
    )
    frame = animator.equalizer(3, 'pondering…')

    assert_includes frame, 'pondering…'
  end

  it 'thinking frames render the equalizer when enabled' do
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    animator = Riffer::Rig::Terminal::Animator.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.start
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until io.string.include?('riffing') || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    animator.stop

    assert_includes io.string, 'riffing'
  end

  it 'thinking frames render reasoning phrases when started in reasoning mode' do
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    animator = Riffer::Rig::Terminal::Animator.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.start(:reasoning)
    phrases = Riffer::Rig::Terminal::Animator::REASONING_PHRASES
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    Process.clock_gettime(Process::CLOCK_MONOTONIC) until phrases.any? do |phrase|
      io.string.include?(phrase)
    end || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    animator.stop

    assert(phrases.any? { |phrase| io.string.include?(phrase) })
  end

  it 'thinking frames return to the neutral label when relabeled out of reasoning' do
    io = tty_io
    animator = Riffer::Rig::Terminal::Animator.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.start(:reasoning)
    await { io.string.include?("\e[K") }
    animator.start
    await { io.string.include?('riffing') }
    animator.stop

    assert_includes io.string, 'riffing'
  end
end
