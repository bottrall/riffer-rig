# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/frame_pty'

class JobsRuntime
  attr_reader :running_job_count

  def initialize(running_job_count)
    @running_job_count = running_job_count
    @observers = []
    @subscribers = []
  end

  def on_message(&block)
    @observers << block
    nil
  end

  def on_job_exit(&block)
    @subscribers << block
    nil
  end

  def start_job
    @running_job_count += 1
    @observers.each(&:call)
  end

  def exit_job
    @running_job_count -= 1
    @subscribers.each(&:call)
  end
end

class RecordingFooter
  attr_reader :counts

  def initialize
    @counts = []
  end

  def jobs(count)
    @counts << count
  end
end

describe Riffer::Rig::Terminal::JobCounter do
  def footer
    @footer ||= RecordingFooter.new
  end

  def counter
    @counter ||= Riffer::Rig::Terminal::JobCounter.new(footer: footer)
  end

  describe '#watch' do
    it 'draws the jobs the Runtime is already running' do
      counter.watch(JobsRuntime.new(2))

      assert_equal [2], footer.counts
    end

    it 'draws the jobs of the Runtime that replaced one with jobs running' do
      counter.watch(JobsRuntime.new(2))

      counter.watch(JobsRuntime.new(0))

      assert_equal [2, 0], footer.counts
    end

    it 'counts a job once the message after its start is recorded' do
      runtime = JobsRuntime.new(0)
      counter.watch(runtime)

      runtime.start_job

      assert_equal [0, 1], footer.counts
    end

    it 'drops a job when it exits' do
      runtime = JobsRuntime.new(2)
      counter.watch(runtime)

      runtime.exit_job

      assert_equal [2, 1], footer.counts
    end
  end

  describe '#refresh' do
    it 'draws a count read before a job exits ahead of the one read after it' do
      runtime = JobsRuntime.new(1)
      counter.watch(runtime)
      parking = [true]
      footer.define_singleton_method(:jobs) do |count|
        Thread.stop if parking.shift
        super(count)
      end

      started = Thread.new { runtime.start_job }
      Thread.pass until started.stop?
      exited = Thread.new { runtime.exit_job }
      Thread.pass until exited.stop?
      started.run
      [started, exited].each(&:join)

      assert_equal [1, 2, 1], footer.counts
    end
  end

  describe 'between turns' do
    before do
      @pty = FramePty.new(columns: 40, rows: 6)
      @frame = Riffer::Rig::Terminal::Frame.new(
        io: @pty.slave,
        theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
        now: -> { Time.new(2026, 1, 1, 14, 32) }
      )
      @frame.start
      @frame.session(tally: -> {})
      @runtime = JobsRuntime.new(3)
      Riffer::Rig::Terminal::JobCounter.new(footer: @frame).watch(@runtime)
    end

    after do
      @frame.stop
      @pty.close
    end

    it 'shows the counter in the idle bar under an idle prompt' do
      assert_includes @pty.screen.rows.last, '3 jobs'
    end

    it 'lowers the counter when a job exits off the prompting thread' do
      Thread.new { @runtime.exit_job }.join

      assert_includes @pty.screen.rows.last, '2 jobs'
    end
  end
end
