# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash::Output do
  def setup
    @tool = Riffer::Rig::Tools::Bash::Output.new
    @jobs = Riffer::Rig::Tools::Bash::Jobs.new(Riffer::Rig::Runtime::JobInbox.new)
    @context = Riffer::Agent::Context.new(cwd: Dir.pwd, jobs: @jobs)
    @max = Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES
  end

  def teardown
    @jobs.shutdown(0.0)
  end

  def start(output)
    reader, writer = IO.pipe
    job = @jobs.register(Process.spawn('sleep 30', pgroup: true), 'sleep 30', reader)
    writer.binmode.write(output)
    writer.close
    sleep 0.01 until File.size(job.output_path) == output.bytesize
    job
  end

  def read(job)
    @tool.call(context: @context, job_id: job.id).content
  end

  it 'ends its description with its guidance sentence' do
    assert Riffer::Rig::Tools::Bash::Output.description.end_with?(
      'Use this to check on a server, watcher or long-running job before it finishes.'
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

  it 'returns the output a job has written' do
    assert_equal 'hello', read(start("hello\n"))
  end

  it 'returns only the output written since the previous read' do
    job = start('first')
    read(job)
    File.write(job.output_path, 'second', mode: 'a')

    assert_equal 'second', read(job)
  end

  it 'replaces a multibyte character split across two reads' do
    job = start("\xC3")
    read(job)
    File.binwrite(job.output_path, "\xA9 after", mode: 'a')

    assert_equal "\u{FFFD} after", read(job)
  end

  it 'returns the head and the truncation marker for output over the limit' do
    job = start("#{'a' * @max}#{'b' * @max}")

    assert_equal "#{'a' * @max}\n[output truncated to #{@max} bytes]", read(job)
  end

  it 'marks truncated output whose cut falls in trailing whitespace' do
    job = start("#{'a' * (@max - 1)}#{"\n" * (@max + 1)}skipped")

    assert read(job).end_with?("[output truncated to #{@max} bytes]")
  end

  it 'reports a read with nothing new' do
    job = start('first')
    read(job)

    assert_equal '(no new output)', read(job)
  end
end
