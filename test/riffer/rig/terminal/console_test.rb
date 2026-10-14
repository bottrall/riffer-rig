# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Console do
  def setup
    @log = []
    @console = Riffer::Rig::Terminal::Console.new(
      output: sized_output,
      frame: recording_frame(@log),
      pipeline: recording_pipeline(@log)
    )
  end

  def sized_output
    Class.new do
      def winsize = [24, 80]
    end.new
  end

  def recording_frame(log)
    Class.new do
      def initialize(log) = @log = log

      def start = @log << :frame_start

      def stop = @log << :frame_stop

      def append(content) = @log << content
    end.new(log)
  end

  def recording_pipeline(log)
    Class.new do
      def initialize(log) = @log = log

      def start = @log << :pipeline_start

      def stop = @log << :pipeline_stop
    end.new(log)
  end

  describe '#start' do
    it 'draws the footer before the keys are read' do
      @console.start

      assert_equal %i[frame_start pipeline_start], @log
    end
  end

  describe '#stop' do
    it 'stops the keys before it erases the footer' do
      @console.stop

      assert_equal %i[pipeline_stop frame_stop], @log
    end

    it 'appends an unfinished line before it erases the footer' do
      @console.print('usage')

      @console.stop

      assert_equal ['usage', :frame_stop], @log.last(2)
    end
  end

  describe '#print' do
    it 'appends a finished line above the footer' do
      @console.print("one\n")

      assert_equal ["one\n"], @log
    end

    it 'holds an unfinished line back' do
      @console.print('one')

      assert_empty @log
    end

    it 'finishes a held line with what follows' do
      @console.print('on')

      @console.print('e', "\n")

      assert_equal ["one\n"], @log
    end

    it 'appends the finished lines of one write together' do
      @console.print("one\ntwo\nthree")

      assert_equal ["one\ntwo\n"], @log
    end

    it 'appends a blank line after a finished one' do
      @console.print("one\n\n")

      assert_equal ["one\n\n"], @log
    end
  end

  describe '#puts' do
    it 'finishes the line' do
      @console.puts('one')

      assert_equal ["one\n"], @log
    end

    it 'leaves a finished line as it is' do
      @console.puts("one\n")

      assert_equal ["one\n"], @log
    end

    it 'writes a blank line without an argument' do
      @console.puts

      assert_equal ["\n"], @log
    end
  end

  describe '#flush' do
    it 'appends nothing' do
      @console.print('one')

      @console.flush

      assert_empty @log
    end
  end

  describe '#tty?' do
    it 'is false' do
      refute_predicate @console, :tty?
    end
  end

  describe '#winsize' do
    it 'is the size of the output' do
      assert_equal [24, 80], @console.winsize
    end
  end

  describe '#settle' do
    it 'appends nothing without an unfinished line' do
      @console.settle

      assert_empty @log
    end

    it 'appends an unfinished line' do
      @console.print('usage')

      @console.settle

      assert_equal ['usage'], @log
    end

    it 'appends an unfinished line only once' do
      @console.print('usage')
      @console.settle

      @console.settle

      assert_equal ['usage'], @log
    end
  end
end
