# frozen_string_literal: true

class Riffer::Rig::Tools::Bash::Kill < Riffer::Tool
  identifier 'bash_kill'
  description 'Send TERM to a background bash job and every process it started. ' \
              'Use this to stop a job that is no longer needed rather than leaving it running.'

  params do
    required :job_id, String, description: 'The job id bash returned for a run_in_background command'
  end

  # @rbs context: Riffer::Agent::Context?
  # @rbs job_id: String
  # @rbs return: Riffer::Tools::Response
  def call(context:, job_id:)
    jobs = context&.[](:jobs) #: Riffer::Rig::Runtime::Jobs?
    return error('no background job registry in the context', type: :command_failed) unless jobs

    job = jobs.kill(job_id)
    return error("No background job #{job_id}", type: :not_found) unless job

    text(job.completed? ? "Job #{job_id} has already exited" : "Sent TERM to job #{job_id}")
  end
end
