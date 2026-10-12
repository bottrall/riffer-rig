# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash::Job do
  def job(status: nil, ended_at: nil)
    Riffer::Rig::Tools::Bash::Job.new(
      id: 'abc123',
      pid: 4242,
      output_path: '/tmp/riffer-rig-job-test',
      started_at: 10.0,
      status: status,
      ended_at: ended_at
    )
  end

  it 'is active without a status' do
    assert_predicate job, :active?
  end

  it 'is completed with a status' do
    assert_predicate job(status: 0), :completed?
  end

  it 'freezes itself' do
    assert_predicate job, :frozen?
  end

  it 'measures elapsed from the given time while active' do
    assert_in_delta(2.5, job.elapsed(12.5))
  end

  it 'measures elapsed to the end time once completed' do
    assert_in_delta(3.0, job(status: 0, ended_at: 13.0).elapsed(99.0))
  end

  it 'returns a completed copy with the status from finish' do
    finished = job.finish(0, 13.0)

    assert_equal 0, finished.status
  end

  it 'returns a completed copy that keeps the identity fields from finish' do
    finished = job.finish(0, 13.0)

    assert_equal [job.id, job.pid, job.output_path, job.started_at],
                 [finished.id, finished.pid, finished.output_path, finished.started_at]
  end

  it 'starts with nothing read' do
    assert_equal 0, job.offset
  end

  it 'returns a copy advanced by the bytes read' do
    assert_equal 12, job.advance(5).advance(7).offset
  end

  it 'returns an advanced copy that keeps its status' do
    assert_equal 0, job(status: 0, ended_at: 13.0).advance(5).status
  end

  it 'returns a completed copy that keeps the offset from finish' do
    assert_equal 5, job.advance(5).finish(0, 13.0).offset
  end
end
