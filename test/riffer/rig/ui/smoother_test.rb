# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class FakeClock
  # Returns instantly, so the tick thread drains as fast as the test allows.
  def sleep(_seconds) = nil
end

describe Riffer::Rig::UI::Smoother do
  def setup
    @io = StringIO.new
    @io.define_singleton_method(:tty?) { true }
    @clock = FakeClock.new
    @smoother = Riffer::Rig::UI::Smoother.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: true), clock: @clock)
  end

  it 'tick is a no op with an empty backlog' do
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

  it 'drain flushes the entire backlog' do
    @smoother << ('a' * 40)
    @smoother.drain

    assert_equal 'a' * 40, @io.string
  end

  it 'drain is a no op with an empty backlog' do
    @smoother.drain

    assert_equal '', @io.string
  end

  it 'writes pass through synchronously when not a tty' do
    pipe = StringIO.new
    smoother = Riffer::Rig::UI::Smoother.new(io: pipe, theme: Riffer::Rig::UI::Theme.new(enabled: false), clock: @clock)

    smoother << 'direct'

    assert_equal 'direct', pipe.string
  end

  it 'start spawns a thread that ticks until stopped' do
    @smoother << 'abcdef'
    @smoother.start
    @smoother.finish

    assert_equal 'abcdef', @io.string
  end

  it 'finish flushes remaining backlog after stopping the thread' do
    @smoother << 'abcdef'
    @smoother.start
    @smoother.finish

    assert_equal 'abcdef', @io.string
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

    assert_equal 'ab', @io.string
  end
end
