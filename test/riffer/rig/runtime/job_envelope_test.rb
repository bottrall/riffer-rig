# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::JobEnvelope do
  def completion(job_id: 'a1b2c3d4', exit_status: 0, tail: "compiled\ndone\n")
    Riffer::Rig::Runtime::JobCompletion.new(
      job_id: job_id,
      command: 'make build',
      exit_status: exit_status,
      duration: 12.34,
      output_path: "/tmp/jobs/#{job_id}",
      tail: tail
    )
  end

  def render(*completions)
    Riffer::Rig::Runtime::JobEnvelope.render(completions)
  end

  describe '.render' do
    it 'wraps an exit in a background-job envelope' do
      envelope = <<~TEXT.chomp
        <background-job id="a1b2c3d4" status="completed" exit-code="0" duration="12.3s">
        <command>make build</command>
        <output-path>/tmp/jobs/a1b2c3d4</output-path>
        <output-tail>
        compiled
        done
        </output-tail>
        </background-job>
      TEXT

      assert_equal envelope, render(completion)
    end

    it 'reports a non-zero exit as failed' do
      assert_includes render(completion(exit_status: 2)), 'status="failed" exit-code="2"'
    end

    it 'says so when the job wrote nothing' do
      assert_includes render(completion(tail: "\n")), "<output-tail>\n(no output)\n</output-tail>"
    end

    it 'batches several exits into one notice' do
      notice = render(completion(job_id: 'aaaa1111'), completion(job_id: 'bbbb2222'))

      assert_equal %w[aaaa1111 bbbb2222], notice.scan(/<background-job id="(\h+)"/).flatten
    end
  end
end
