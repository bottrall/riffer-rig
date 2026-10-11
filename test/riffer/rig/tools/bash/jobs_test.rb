# frozen_string_literal: true

require 'securerandom'
require 'test_helper'

describe Riffer::Rig::Tools::Bash::Jobs do
  def setup
    @jobs = Riffer::Rig::Tools::Bash::Jobs.new
  end

  def spawn_pgroup(command)
    Process.spawn(command, pgroup: true)
  end

  def output_path
    File.join(Dir.tmpdir, "riffer-rig-job-test-#{SecureRandom.hex(4)}")
  end

  def stop_group(pid)
    Process.kill('KILL', -Process.getpgid(pid))
  rescue Errno::ESRCH
    nil
  end

  def completed_job(command)
    pid = spawn_pgroup(command)
    job = @jobs.register(pid, output_path)
    completed = nil
    50.times do
      completed = @jobs.list.find { |candidate| candidate.id == job.id && candidate.completed? }
      break if completed

      sleep 0.02
    end
    [job, completed]
  ensure
    stop_group(pid)
  end

  it 'registers a job with the spawned pid' do
    pid = spawn_pgroup('sleep 5')
    registered = @jobs.register(pid, output_path)

    assert_equal pid, registered.pid
  ensure
    stop_group(pid)
  end

  it 'registers a job with the given output path' do
    pid = spawn_pgroup('sleep 5')
    path = output_path
    registered = @jobs.register(pid, path)

    assert_equal path, registered.output_path
  ensure
    stop_group(pid)
  end

  it 'registers a job as active' do
    pid = spawn_pgroup('sleep 5')
    registered = @jobs.register(pid, output_path)

    assert_predicate registered, :active?
  ensure
    stop_group(pid)
  end

  it 'keys each job by a distinct id' do
    first = @jobs.register(spawn_pgroup('sleep 5'), output_path)
    second = @jobs.register(spawn_pgroup('sleep 5'), output_path)

    refute_equal first.id, second.id
  ensure
    @jobs.kill_outstanding
  end

  it 'lists the registered jobs' do
    pid = spawn_pgroup('sleep 5')
    registered = @jobs.register(pid, output_path)

    assert_includes @jobs.list.map(&:id), registered.id
  ensure
    stop_group(pid)
  end

  it 'reports a finished job as completed with its exit status' do
    _job, completed = completed_job('true')

    assert_equal 0, completed&.status
  end

  it 'reports a finished job with elapsed time to its completion' do
    _job, completed = completed_job('sleep 0.3')

    assert_operator completed.elapsed(Process.clock_gettime(Process::CLOCK_MONOTONIC)), :>=, 0.2
  end

  it 'sweeps completed jobs so later touches no longer list them' do
    job, _completed = completed_job('true')

    refute_includes @jobs.list.map(&:id), job.id
  end

  it 'kills outstanding process groups' do
    pid = spawn_pgroup('sleep 30')
    job = @jobs.register(pid, output_path)
    @jobs.kill_outstanding
    killed = nil
    50.times do
      killed = @jobs.list.find { |candidate| candidate.id == job.id && candidate.completed? }
      break if killed

      sleep 0.02
    end

    assert killed
  end
end
