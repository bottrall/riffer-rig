# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class Riffer::Rig::UI::SmootherTest < Minitest::Test
  def setup
    @io = StringIO.new
    @io.define_singleton_method(:tty?) { true }
    @clock = FakeClock.new
    @smoother = Riffer::Rig::UI::Smoother.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: true), clock: @clock)
  end

  def test_tick_is_a_no_op_with_an_empty_backlog
    @smoother.tick

    assert_equal '', @io.string
  end

  def test_tick_releases_at_least_the_minimum_chars
    @smoother << 'a'
    @smoother.tick

    assert_equal 'a', @io.string
  end

  def test_tick_releases_a_proportional_slice_of_the_backlog
    @smoother << ('a' * 120)
    @smoother.tick

    assert_equal 'a' * 2, @io.string
  end

  def test_tick_releases_the_whole_backlog_when_smaller_than_the_slice
    @smoother << 'a'
    @smoother.tick

    assert_equal 'a', @io.string
  end

  def test_successive_ticks_keep_draining
    @smoother << ('a' * 120)
    @smoother.tick
    @smoother.tick

    assert_equal 'a' * 4, @io.string
  end

  def test_drain_flushes_the_entire_backlog
    @smoother << ('a' * 40)
    @smoother.drain

    assert_equal 'a' * 40, @io.string
  end

  def test_drain_is_a_no_op_with_an_empty_backlog
    @smoother.drain

    assert_equal '', @io.string
  end

  def test_writes_pass_through_synchronously_when_not_a_tty
    pipe = StringIO.new
    smoother = Riffer::Rig::UI::Smoother.new(io: pipe, theme: Riffer::Rig::UI::Theme.new(enabled: false), clock: @clock)

    smoother << 'direct'

    assert_equal 'direct', pipe.string
  end

  def test_start_spawns_a_thread_that_ticks_until_stopped
    @smoother << 'abcdef'
    @smoother.start
    @smoother.finish

    assert_equal 'abcdef', @io.string
  end

  def test_finish_flushes_remaining_backlog_after_stopping_the_thread
    @smoother << 'abcdef'
    @smoother.start
    @smoother.finish

    assert_equal 'abcdef', @io.string
  end

  def test_finish_without_start_does_not_raise
    @smoother.finish

    assert_equal '', @io.string
  end

  def test_finish_is_safe_to_call_twice
    @smoother << 'ab'
    @smoother.start
    @smoother.finish
    @smoother.finish

    assert_equal 'ab', @io.string
  end

  class FakeClock
    # Returns instantly, so the tick thread drains as fast as the test allows.
    def sleep(_seconds) = nil
  end
end
