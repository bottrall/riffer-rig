# frozen_string_literal: true

require 'securerandom'
require 'test_helper'

describe Riffer::Rig::Tools::Bash::Poll do
  def setup
    @tool = Riffer::Rig::Tools::Bash::Poll.new
    @jobs = Riffer::Rig::Tools::Bash::Jobs.new
    @context = Riffer::Agent::Context.new(cwd: Dir.pwd, jobs: @jobs)
  end

  def teardown
    @jobs.kill_outstanding
  end

  def spawn_job(command)
    response = Riffer::Rig::Tools::Bash.new.call(context: @context, command: command, run_in_background: true)
    response.content[/\AJob (\h{8})/, 1]
  end

  def poll(job_id, wait_ms: 0, context: @context)
    @tool.call(context: context, job_id: job_id, wait_ms: wait_ms)
  end

  it 'returns the output and exit status of a finished job' do
    assert_equal "hello\n[exited with status 0]", poll(spawn_job('echo hello'), wait_ms: 2000).content
  end

  it 'is a tool error when the job exited non-zero' do
    assert_predicate poll(spawn_job('exit 3'), wait_ms: 2000), :error?
  end

  it 'reports a non-zero exit status' do
    assert_includes poll(spawn_job('exit 3'), wait_ms: 2000).content, '[exited with status 3]'
  end

  it 'returns as soon as the job exits, before the wait runs out' do
    job_id = spawn_job('true')
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    poll(job_id, wait_ms: 5000)

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
  end

  it 'reports a job that is still running' do
    assert_equal "(no new output)\n[running]", poll(spawn_job('sleep 30')).content
  end

  it 'returns the buffered output of a running job' do
    assert_includes poll(spawn_job('echo early; sleep 30'), wait_ms: 300).content, 'early'
  end

  it 'marks a wait that ran out as timed out with the job still running' do
    assert_equal "(no new output)\n[timed out after 1s]\n[running]", poll(spawn_job('sleep 30'), wait_ms: 600).content
  end

  it 'returns only the output written since the last poll' do
    job_id = spawn_job('echo first; sleep 0.5; echo second')
    poll(job_id, wait_ms: 250)

    assert_equal "second\n[exited with status 0]", poll(job_id, wait_ms: 2000).content
  end

  it 'collects output larger than a pipe buffer' do
    job_id = spawn_job('head -c 200000 /dev/zero | tr "\\0" a')

    assert_includes poll(job_id, wait_ms: 5000).content, '[exited with status 0]'
  end

  it 'truncates output over the limit' do
    job_id = spawn_job('head -c 200000 /dev/zero | tr "\\0" a')

    assert_includes poll(job_id, wait_ms: 5000).content, '[output truncated to'
  end

  def job_with_output(command, output)
    path = File.join(Dir.tmpdir, "riffer-rig-job-test-#{SecureRandom.hex(4)}")
    File.binwrite(path, output)
    @jobs.register(Process.spawn(command, pgroup: true), path).id
  end

  def over_read_limit(head)
    "#{head}#{'b' * Riffer::Rig::Tools::Bash::Jobs::READ_LIMIT_BYTES}"
  end

  it 'returns the head and the truncation marker for output over the read limit' do
    max = Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES
    job_id = job_with_output('sleep 30', over_read_limit('a' * max))

    assert_equal "#{'a' * max}\n[output truncated to #{max} bytes]\n[running]", poll(job_id).content
  end

  it 'does not return the output it skipped on the next poll' do
    job_id = job_with_output('sleep 30', over_read_limit('a' * Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES))
    poll(job_id)

    assert_equal "(no new output)\n[running]", poll(job_id).content
  end

  it 'reports the exit status of a finished job with output over the read limit' do
    job_id = job_with_output('exit 3', over_read_limit('a' * Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES))

    assert poll(job_id, wait_ms: 2000).content.end_with?("bytes]\n[exited with status 3]")
  end

  it 'marks truncated output whose cut falls in trailing whitespace' do
    max = Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES
    job_id = job_with_output('sleep 30', "#{'a' * (max - 1)}#{"\n" * max}")

    assert_includes poll(job_id).content, "[output truncated to #{max} bytes]"
  end

  it 'returns valid text when the cut splits a multibyte character' do
    max = Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES
    job_id = job_with_output('sleep 30', over_read_limit("#{'a' * (max - 1)}\u00e9"))

    assert_predicate poll(job_id).content, :valid_encoding?
  end

  it 'returns valid text when a poll starts inside a multibyte character' do
    job_id = job_with_output('sleep 30', "\xC3")
    poll(job_id)
    File.binwrite(@jobs.list.first.output_path, "\xA9 after", mode: 'a')

    assert_equal "\uFFFD after\n[running]", poll(job_id).content
  end

  it 'forgets a job once its exit status is collected' do
    job_id = spawn_job('true')
    poll(job_id, wait_ms: 2000)

    assert_predicate poll(job_id), :error?
  end

  it 'is a tool error for an unknown job' do
    assert_equal 'No background job missing1', poll('missing1').content
  end

  it 'is a tool error without a job registry in its context' do
    assert_predicate poll('missing1', context: Riffer::Agent::Context.new(cwd: Dir.pwd)), :error?
  end

  def poll_cancelled_after(seconds, job_id)
    flag = Riffer::Rig::Runtime::CancelFlag.new
    canceller = Thread.new do
      sleep seconds
      flag.set
    end
    poll(job_id, wait_ms: 30_000, context: Riffer::Agent::Context.new(cwd: Dir.pwd, jobs: @jobs, cancel_flag: flag))
  ensure
    canceller.join
  end

  it 'returns within a second of a cancel' do
    job_id = spawn_job('sleep 30')
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    poll_cancelled_after(0.2, job_id)

    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.2
  end

  it 'tells the model the wait was cancelled' do
    assert_includes poll_cancelled_after(0.2, spawn_job('sleep 30')).content, '[cancelled]'
  end

  it 'reports the cancel as a tool error' do
    assert_predicate poll_cancelled_after(0.2, spawn_job('sleep 30')), :error?
  end

  it 'keeps the state line of a job still running below the cancel marker' do
    assert poll_cancelled_after(0.2, spawn_job('sleep 30')).content.end_with?("[cancelled]\n[running]")
  end

  def poll_after_runtime_cancel(job_id)
    flag = Riffer::Rig::Runtime::CancelFlag.new
    pid = @jobs.list.first.pid
    flag.set
    @jobs.kill_outstanding
    # A poll returns on its first read once the flag is set, so the job has to
    # be reapable before it starts.
    100.times { `ps -o stat= -p #{pid}`.start_with?('Z') ? break : sleep(0.02) }
    poll(job_id, wait_ms: 30_000, context: Riffer::Agent::Context.new(cwd: Dir.pwd, jobs: @jobs, cancel_flag: flag))
  end

  it 'marks the wait cancelled when the cancel also killed the job' do
    assert_includes poll_after_runtime_cancel(spawn_job('sleep 30')).content, '[cancelled]'
  end

  it 'reports the exit status of a job the cancel killed' do
    assert poll_after_runtime_cancel(spawn_job('sleep 30')).content.end_with?("[cancelled]\n[exited with status 1]")
  end

  it 'is a tool error when the cancel killed the job' do
    assert_predicate poll_after_runtime_cancel(spawn_job('sleep 30')), :error?
  end

  it 'ends its description with its guidance sentence' do
    assert Riffer::Rig::Tools::Bash::Poll.description.end_with?(
      'Pass wait_ms to block until the job exits rather than polling in a loop.'
    )
  end
end
