# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class FakeClock
  def sleep(_seconds) = nil
end

describe Riffer::Rig::Terminal::Smoother do
  def setup
    @io = StringIO.new
    @io.define_singleton_method(:tty?) { true }
    @clock = FakeClock.new
    @smoother = Riffer::Rig::Terminal::Smoother.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: true),
      clock: @clock
    )
  end

  def smoother_on(io, enabled:)
    Riffer::Rig::Terminal::Smoother.new(
      io: io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: enabled),
      clock: @clock
    )
  end

  it 'start spawns no thread when smoothing is disabled' do
    smoother = smoother_on(@io, enabled: false)
    before = Thread.list
    smoother.start
    spawned = Thread.list - before
    smoother.finish

    assert_empty spawned
  end

  it 'start spawns a single thread when called twice' do
    before = Thread.list
    @smoother.start
    @smoother.start
    spawned = Thread.list - before
    @smoother.finish

    assert_equal 1, spawned.size
  end

  it 'writes pass through synchronously when not a tty' do
    pipe = StringIO.new
    smoother = Riffer::Rig::Terminal::Smoother.new(
      io: pipe,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      clock: @clock
    )

    smoother << 'direct'

    assert_equal 'direct', pipe.string
  end

  it 'writes pass through when the theme is disabled on a tty' do
    smoother_on(@io, enabled: false) << 'direct'

    assert_equal 'direct', @io.string
  end

  it 'writes pass through when the theme is enabled off a tty' do
    pipe = StringIO.new
    smoother_on(pipe, enabled: true) << 'direct'

    assert_equal 'direct', pipe.string
  end

  it 'tick is a no op with an empty backlog' do
    @smoother.tick

    assert_equal '', @io.string
  end

  it 'tick accrues nothing while the backlog is empty' do
    5.times { @smoother.tick }
    @smoother << 'a'
    @smoother.tick

    assert_equal '', @io.string
  end

  it 'tick accrues a sub character floor across ticks' do
    @smoother << 'a'
    @smoother.tick

    assert_equal '', @io.string
  end

  it 'accrued floor emits once it reaches a character' do
    @smoother << 'a'
    6.times { @smoother.tick }

    assert_equal 'a', @io.string
  end

  it 'tick releases a proportional slice of the backlog' do
    @smoother << ('a' * 120)
    @smoother.tick

    assert_equal 'a' * 2, @io.string
  end

  it 'successive ticks keep draining' do
    @smoother << ('a' * 120)
    @smoother.tick
    @smoother.tick

    assert_equal 'a' * 3, @io.string
  end

  it 'drain flushes the backlog and appends a newline when it lacks one' do
    @smoother << ('a' * 40)
    @smoother.drain

    assert_equal "#{'a' * 40}\n", @io.string
  end

  it 'drain adds only the missing newline after a partial prose block' do
    @smoother << 'partial line'
    @smoother.drain

    assert_equal "partial line\n", @io.string
  end

  it 'drain adds no blank line after a prose block that already ended cleanly' do
    @smoother << "complete line\n"
    @smoother.drain

    assert_equal "complete line\n", @io.string
  end

  it 'drain adds the missing newline after ticks emptied the backlog' do
    @smoother << 'a'
    6.times { @smoother.tick }
    @smoother.drain

    assert_equal "a\n", @io.string
  end

  it 'drain adds no newline after ticks released one' do
    @smoother << "\n"
    6.times { @smoother.tick }
    @smoother.drain

    assert_equal "\n", @io.string
  end

  it 'drain adds the missing newline after a pass through write' do
    smoother = smoother_on(@io, enabled: false)
    smoother << 'direct'
    smoother.drain

    assert_equal "direct\n", @io.string
  end

  it 'drain adds no newline after a pass through write that ended cleanly' do
    smoother = smoother_on(@io, enabled: false)
    smoother << "direct\n"
    smoother.drain

    assert_equal "direct\n", @io.string
  end

  it 'drain is a no op with an empty backlog' do
    @smoother.drain

    assert_equal '', @io.string
  end

  it 'finish flushes remaining backlog after stopping the thread' do
    @smoother << 'abcdef'
    @smoother.start
    @smoother.finish

    assert_equal "abcdef\n", @io.string
  end

  it 'finish without start does not raise' do
    @smoother.finish

    assert_equal '', @io.string
  end

  it 'finish is safe to call twice' do
    @smoother << 'ab'
    @smoother.start
    @smoother.finish
    @smoother.finish

    assert_equal "ab\n", @io.string
  end
end
