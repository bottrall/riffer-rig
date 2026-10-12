# frozen_string_literal: true

class Riffer::Rig::Tools::Bash::Kill < Riffer::Tool
  identifier 'bash_kill'
  description 'Terminate a background bash job and every process it started. ' \
              'Poll the job afterwards to collect its remaining output and exit status.'

  params do
    required :job_id, String, description: 'The job id bash returned for a run_in_background command'
  end

  # @rbs context: Riffer::Agent::Context?
  # @rbs job_id: String
  # @rbs return: Riffer::Tools::Response
  def call(context:, job_id:)
    jobs = context&.[](:jobs) #: Riffer::Rig::Tools::Bash::Jobs?
    return error('no background job registry in the context', type: :command_failed) unless jobs
    return error("No background job #{job_id}", type: :not_found) unless jobs.kill(job_id)

    text("Job #{job_id} terminated")
  end
end
