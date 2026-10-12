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

  def register_writer(command)
    path = output_path
    @jobs.register(Process.spawn(command, pgroup: true, out: [path, 'w', 0o600]), path)
  end

  def register_with_output(command, output)
    path = output_path
    File.binwrite(path, output)
    @jobs.register(spawn_pgroup(command), path)
  end

  def poll_until_completed(id)
    output = +''
    50.times do
      job, chunk = @jobs.poll(id)
      output << chunk
      return [job, output] if job.completed?

      sleep 0.02
    end
    nil
  end

  it 'polls the output a job has written' do
    job = register_writer('echo hello')

    assert_equal "hello\n", poll_until_completed(job.id)&.last
  ensure
    @jobs.kill_outstanding
  end

  it 'polls the exit status of a finished job' do
    job = register_writer('exit 3')

    assert_equal 3, poll_until_completed(job.id)&.first&.status
  ensure
    @jobs.kill_outstanding
  end

  it 'polls a running job as active' do
    job = register_writer('sleep 5')

    assert_predicate @jobs.poll(job.id)&.first, :active?
  ensure
    @jobs.kill_outstanding
  end

  it 'polls only the output written since the last poll' do
    job = register_with_output('sleep 5', 'first')
    @jobs.poll(job.id)
    File.write(job.output_path, 'second', mode: 'a')

    assert_equal 'second', @jobs.poll(job.id)&.last
  ensure
    @jobs.kill_outstanding
  end

  it 'polls no more than the read limit at once' do
    limit = Riffer::Rig::Tools::Bash::Jobs::READ_LIMIT_BYTES
    job = register_with_output('sleep 5', "#{'a' * limit}skipped")

    assert_equal 'a' * limit, @jobs.poll(job.id)&.last
  ensure
    @jobs.kill_outstanding
  end

  it 'skips the output beyond the read limit on the next poll' do
    job = register_with_output('sleep 5', 'a' * (Riffer::Rig::Tools::Bash::Jobs::READ_LIMIT_BYTES + 7))
    @jobs.poll(job.id)
    File.write(job.output_path, 'tail', mode: 'a')

    assert_equal 'tail', @jobs.poll(job.id)&.last
  ensure
    @jobs.kill_outstanding
  end

  it 'polls the exit status of a finished job with more output than the read limit' do
    job = register_with_output('exit 3', 'a' * (Riffer::Rig::Tools::Bash::Jobs::READ_LIMIT_BYTES + 7))

    assert_equal 3, poll_until_completed(job.id)&.first&.status
  ensure
    @jobs.kill_outstanding
  end

  it 'polls nothing new as an empty string' do
    job = register_with_output('sleep 5', '')

    assert_equal '', @jobs.poll(job.id)&.last
  ensure
    @jobs.kill_outstanding
  end

  it 'polls output in the default external encoding' do
    job = register_with_output('sleep 5', 'hello')

    assert_equal Encoding.default_external, @jobs.poll(job.id)&.last&.encoding
  ensure
    @jobs.kill_outstanding
  end

  it 'sweeps a job once a poll reports it completed' do
    job = register_writer('true')
    poll_until_completed(job.id)

    assert_nil @jobs.poll(job.id)
  end

  it 'polls an unknown job as nil' do
    assert_nil @jobs.poll('missing1')
  end

  it 'kills the process group of a job' do
    job = register_writer('sleep 30')
    @jobs.kill(job.id)

    assert poll_until_completed(job.id)
  end

  it 'returns the job it killed' do
    job = register_writer('sleep 30')

    assert_equal job.id, @jobs.kill(job.id)&.id
  ensure
    @jobs.kill_outstanding
  end

  it 'kills an unknown job as nil' do
    assert_nil @jobs.kill('missing1')
  end
end
