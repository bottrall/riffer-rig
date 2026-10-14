# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Console do
  def setup
    @log = []
    @console = Riffer::Rig::Terminal::Console.new(frame: recording_frame(@log), pipeline: recording_pipeline(@log))
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
  end

  describe '#print' do
    it 'appends the chunks of one write together above the footer' do
      @console.print('on', "e\n")

      assert_equal ["one\n"], @log
    end

    it 'appends nothing for an empty write' do
      @console.print('')

      assert_empty @log
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
      @console.flush

      assert_empty @log
    end
  end

  describe '#tty?' do
    it 'is false' do
      refute_predicate @console, :tty?
    end
  end
end
