# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Terminal::Animator do
  def setup
    @io = StringIO.new
    @animator = Riffer::Rig::Terminal::Animator.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
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
    animator = Riffer::Rig::Terminal::Animator.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.start
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until io.string.include?('riffing') || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    animator.stop

    assert_includes io.string, 'riffing'
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

  it 'renders the described activity in the status line' do
    animator = running_animator
    animator.describe('read(path: "a.rb")')
    wait_for(animator, animator_output) { |io| io.string.include?('read(path: "a.rb")') }
    animator.stop

    assert_includes animator_output.string, 'read(path: "a.rb")'
  end

  it 'renders elapsed time and running cost in the status line' do
    animator = running_animator
    animator.cost(0.25)
    wait_for(animator, animator_output) { |io| io.string.include?('~$0.2500') }
    animator.stop

    output = animator_output.string

    assert_includes output, '~$0.2500'
    assert_match(/\d+s · ~\$0\.2500/, output)
  end

  it 'keeps a described activity across a stop and start' do
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    animator = Riffer::Rig::Terminal::Animator.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.describe('bash(command: "ls")')
    animator.start
    wait_for(animator, io) { |frame_io| frame_io.string.include?('bash(command: "ls")') }

    assert_includes io.string, 'bash(command: "ls")'
  end

  def running_animator
    @animator_output = StringIO.new
    @animator_output.define_singleton_method(:tty?) { true }
    animator = Riffer::Rig::Terminal::Animator.new(
      io: @animator_output,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: true)
    )
    animator.start
    animator
  end

  attr_reader :animator_output

  def wait_for(animator, io)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until yield(io) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    animator.stop
  end
end
