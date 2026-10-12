# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash::Kill do
  def setup
    @tool = Riffer::Rig::Tools::Bash::Kill.new
    @jobs = Riffer::Rig::Tools::Bash::Jobs.new
    @context = Riffer::Agent::Context.new(cwd: Dir.pwd, jobs: @jobs)
  end

  def teardown
    @jobs.kill_outstanding
  end

  def spawn_job(command)
    Riffer::Rig::Tools::Bash.new.call(context: @context, command: command, run_in_background: true).content
  end

  def job_id(spawned)
    spawned[/\AJob (\h{8})/, 1]
  end

  def poll(job_id, wait_ms)
    Riffer::Rig::Tools::Bash::Poll.new.call(context: @context, job_id: job_id, wait_ms: wait_ms)
  end

  it 'reports the job as terminated' do
    id = job_id(spawn_job('sleep 30'))

    assert_equal "Job #{id} terminated", @tool.call(context: @context, job_id: id).content
  end

  it 'ends the job' do
    id = job_id(spawn_job('sleep 30'))
    @tool.call(context: @context, job_id: id)

    assert_includes poll(id, 2000).content, '[exited with status'
  end

  it 'terminates the processes the job started, not just the job' do
    spawned = spawn_job('(sleep 0.4; echo survived) & wait')
    @tool.call(context: @context, job_id: job_id(spawned))
    sleep 0.8

    refute_includes File.read(spawned.split("\n").last.delete_prefix('Output: ')), 'survived'
  end

  it 'is a tool error for an unknown job' do
    assert_equal 'No background job missing1', @tool.call(context: @context, job_id: 'missing1').content
  end

  it 'is a tool error without a job registry in its context' do
    response = @tool.call(context: Riffer::Agent::Context.new(cwd: Dir.pwd), job_id: 'missing1')

    assert_predicate response, :error?
  end

  it 'ends its description with its guidance sentence' do
    assert Riffer::Rig::Tools::Bash::Kill.description.end_with?(
      'Poll the job afterwards to collect its remaining output and exit status.'
    )
  end
end
