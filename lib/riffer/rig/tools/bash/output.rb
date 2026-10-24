# frozen_string_literal: true

class Riffer::Rig::Tools::Bash::Output < Riffer::Tool
  include Riffer::Rig::Tools::Bash::Truncation

  identifier 'bash_output'
  description 'Return what a background bash job has written since the last read of it. ' \
              'Use this to check on a server, watcher or long-running job before it finishes.'

  params do
    required :job_id, String, description: 'The job id bash returned for a run_in_background command'
  end

  # @rbs context: Riffer::Agent::Context?
  # @rbs job_id: String
  # @rbs return: Riffer::Tools::Response
  def call(context:, job_id:)
    jobs = context&.[](:jobs) #: Riffer::Rig::Runtime::Jobs?
    return error('no background job registry in the context', type: :command_failed) unless jobs

    # Read past the cut, so truncate marks the output it drops.
    output = jobs.read(job_id, 2 * Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES)&.last
    return error("No background job #{job_id}", type: :not_found) unless output

    # A read starts at a byte offset and stops at a byte limit, either of which
    # can split a multibyte character. Stripping first could shrink a read back
    # under the limit and lose the marker for the output skipped behind it.
    output = truncate(output.scrub).rstrip
    text(output.empty? ? '(no new output)' : output)
  end
end
