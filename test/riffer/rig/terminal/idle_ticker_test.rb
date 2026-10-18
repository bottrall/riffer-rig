# frozen_string_literal: true

require 'test_helper'

class TickingFrame
  attr_reader :ticks

  def initialize = @ticks = Queue.new

  def idle_tick = @ticks << true
end

describe Riffer::Rig::Terminal::IdleTicker do
  def setup
    @frame = TickingFrame.new
    @ticker = nil
  end

  def teardown
    @ticker&.stop
  end

  def ticker = @ticker ||= Riffer::Rig::Terminal::IdleTicker.new(footer: @frame)

  def await
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    Thread.pass until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  describe '#start' do
    it 'ticks the footer once a second until it is stopped' do
      ticker.start
      await { !@frame.ticks.empty? }
      @ticker = ticker

      assert @frame.ticks.pop
    end
  end

  describe '#stop' do
    it 'ticks no more once it is stopped' do
      ticker.start
      await { !@frame.ticks.empty? }
      ticker.stop
      @frame.ticks.pop
      sleep(Riffer::Rig::Terminal::IdleTicker::TICK_SECONDS * 1.2)

      assert_empty @frame.ticks
    end
  end
end
