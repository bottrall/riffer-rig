# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash::Kill do
  def setup
    @tool = Riffer::Rig::Tools::Bash::Kill.new
    @exits = Queue.new
    inbox = Riffer::Rig::Runtime::JobInbox.new
    inbox.subscribe { |completion| @exits << completion }
    @jobs = Riffer::Rig::Tools::Bash::Jobs.new(inbox)
    @context = Riffer::Agent::Context.new(cwd: Dir.pwd, jobs: @jobs)
  end

  def teardown
    @jobs.shutdown(0.0)
  end

  def start(command)
    @jobs.register(Process.spawn(command, pgroup: true), command, File::NULL)
  end

  def kill(job)
    @tool.call(context: @context, job_id: job.id).content
  end

  it 'ends its description with its guidance sentence' do
    assert Riffer::Rig::Tools::Bash::Kill.description.end_with?(
      'Use this to stop a job that is no longer needed rather than leaving it running.'
    )
  end

  it 'is a tool error without a job registry in its context' do
    response = @tool.call(context: Riffer::Agent::Context.new(cwd: Dir.pwd), job_id: 'missing1')

    assert_predicate response, :error?
  end

  it 'is a tool error for an unknown job' do
    response = @tool.call(context: @context, job_id: 'missing1')

    assert_equal [:not_found, 'No background job missing1'], [response.error_type, response.content]
  end

  it 'ends the job' do
    job = start('sleep 30')
    kill(job)

    assert_equal job.id, @exits.pop(timeout: 5)&.job_id
  end

  it 'reports the signal it sent to a running job' do
    job = start('sleep 30')

    assert_equal "Sent TERM to job #{job.id}", kill(job)
  end

  it 'reports a job that has already exited' do
    job = start('true')
    @exits.pop(timeout: 5)

    assert_equal "Job #{job.id} has already exited", kill(job)
  end
end
