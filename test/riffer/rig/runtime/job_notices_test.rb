# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::JobNotices do
  before do
    @listed = []
    @exited = []
    @inbox = Riffer::Rig::Runtime::JobInbox.new
    @emitted = []
    @delivered = []
    @session = Riffer::Agent::Session.new(messages: [Riffer::Messages::User.new('go')])
  end

  def jobs
    listed = @listed
    exited = @exited
    Class.new do
      define_method(:list) { listed }
      define_method(:consume) { exited.slice!(0..) }
    end.new
  end

  def listed_job(running)
    Riffer::Rig::Runtime::Job.new(
      id: 'a1b2c3d4', pid: 1, command: 'make', output_path: '/tmp/out', started_at: 0.0, ended_at: (1.0 unless running)
    )
  end

  def notices
    Riffer::Rig::Runtime::JobNotices.new(
      jobs, @inbox, emit: ->(event) { @emitted << event }, deliver: ->(message) { @delivered << message }
    )
  end

  def completion(job_id = 'a1b2c3d4')
    Riffer::Rig::Runtime::JobCompletion.new(
      job_id: job_id, command: 'make', exit_status: 0, signal: nil, duration: 1.0, output_path: '/tmp/out', tail: 'done'
    )
  end

  def tool_result(content = 'listed')
    Riffer::Messages::Tool.new(content, tool_call_id: 'call-1', name: 'bash')
  end

  describe '#running_count' do
    it 'counts the jobs still running' do
      @listed.push(listed_job(true), listed_job(false), listed_job(true))

      assert_equal 2, notices.running_count
    end
  end

  describe '#pending?' do
    it 'is true while a job is listed' do
      @listed << listed_job(false)

      assert_predicate notices, :pending?
    end

    it 'is false with no job listed' do
      refute_predicate notices, :pending?
    end
  end

  describe '#await' do
    it 'is false when no exit arrives before the timeout' do
      refute notices.await(0.01)
    end
  end

  describe '#pending_exit_count' do
    it 'counts the exits waiting in the inbox' do
      @inbox.push(completion)

      assert_equal 1, notices.pending_exit_count
    end
  end

  describe '#with_notice' do
    it 'returns the result unchanged without an exit' do
      message = tool_result

      assert_same message, notices.with_notice(message, @session)
    end

    it 'appends the exits to the result' do
      @exited << completion

      assert_equal "listed\n\n#{Riffer::Rig::Runtime::JobEnvelope.render([completion])}",
                   notices.with_notice(tool_result, @session).content
    end

    it 'replaces the result in the session' do
      message = tool_result
      @session.add(message)
      @exited << completion
      noticed = notices.with_notice(message, @session)

      assert_same noticed, @session.messages.last
    end

    it 'emits a job_exit for each exit' do
      @exited.push(completion('a'), completion('b'))
      notices.with_notice(tool_result, @session)

      assert_equal %w[a b], @emitted.map(&:job_id)
    end
  end

  describe '#notify' do
    it 'adds nothing without an exit' do
      assert_nil notices.notify(@session)
    end

    it 'adds a job notification to the session' do
      @exited << completion
      notices.notify(@session)

      assert_instance_of Riffer::Rig::Runtime::JobNotification, @session.messages.last
    end

    it 'delivers the notification' do
      @exited << completion
      notification = notices.notify(@session)

      assert_equal [notification], @delivered
    end

    it 'counts the exits a follow-up reports' do
      @exited.push(completion('a'), completion('b'))

      assert_equal 2, notices.notify(@session, follow_up: true)&.follow_up_exits
    end

    it 'leaves the count off outside a follow-up' do
      @exited << completion

      assert_nil notices.notify(@session)&.follow_up_exits
    end
  end
end
