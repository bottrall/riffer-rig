# frozen_string_literal: true

require 'test_helper'

class LoadingFrame
  attr_reader :lines

  def initialize
    @lines = []
    @loading = true
  end

  def loading(line) = @lines << line

  def loading? = @loading

  def end_loading = @loading = false
end

describe Riffer::Rig::Terminal::Loading do
  def setup
    @frame = LoadingFrame.new
  end

  def teardown
    @loader&.stop
  end

  def loader
    @loader ||= Riffer::Rig::Terminal::Loading.new(frame: @frame, random: Random.new(1))
  end

  def lines = @frame.lines

  def await
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    Thread.pass until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  describe '#start' do
    it 'draws the first frame of the spinner with a quip' do
      loader.start

      assert_equal '⠋ dusting off the vinyl…', lines.first
    end
  end

  describe '#tick' do
    it 'steps the spinner through its frames' do
      3.times { loader.tick }

      assert_equal ['⠋ dusting off the vinyl…', '⠙ dusting off the vinyl…', '⠹ dusting off the vinyl…'], lines
    end

    it 'wraps the spinner back to its first frame' do
      (Riffer::Rig::Terminal::Loading::FRAMES.size + 1).times { loader.tick }

      assert_equal '⠋', lines.last.split.first
    end

    it 'keeps the quip it rolled until its turn ends' do
      (Riffer::Rig::Terminal::Loading::QUIP_TICKS - 1).times { loader.tick }

      assert_equal 1, lines.map { |line| line.sub(/^\S+ /, '') }.uniq.size
    end

    it 'rolls a new quip when the turn ends' do
      (Riffer::Rig::Terminal::Loading::QUIP_TICKS + 1).times { loader.tick }

      assert_equal '⠇ finding the groove…', lines.last
    end

    it 'draws nothing once the loading row is gone' do
      loader.tick
      @frame.end_loading

      loader.tick

      assert_equal 1, lines.size
    end

    it 'ends its thread once the loading row is gone' do
      running = Thread.list
      loader.start
      @frame.end_loading
      await { (Thread.list - running).empty? }

      assert_empty Thread.list - running
    end
  end

  describe '#stop' do
    it 'ends the thread that draws the frames' do
      running = Thread.list
      loader.start

      loader.stop

      assert_empty Thread.list - running
    end
  end
end
