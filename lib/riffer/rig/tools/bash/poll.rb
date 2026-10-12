# frozen_string_literal: true

class Riffer::Rig::Tools::Bash::Poll < Riffer::Tool
  include Riffer::Rig::Tools::Bash::MonotonicClock
  include Riffer::Rig::Tools::Bash::Truncation

  identifier 'bash_poll'
  description 'Collect what a background bash job has written since the last poll, ending in [running] or, ' \
              'once it has finished, [exited with status N]. ' \
              'Pass wait_ms to block until the job exits rather than polling in a loop.'

  timeout 600

  params do
    required :job_id, String, description: 'The job id bash returned for a run_in_background command'
    optional :wait_ms,
             Integer,
             description: 'Wait up to this many milliseconds for the job to exit before returning',
             default: 0
  end

  # @rbs context: Riffer::Agent::Context?
  # @rbs job_id: String
  # @rbs wait_ms: Integer
  # @rbs return: Riffer::Tools::Response
  def call(context:, job_id:, wait_ms: 0)
    jobs = context&.[](:jobs) #: Riffer::Rig::Tools::Bash::Jobs?
    return error('no background job registry in the context', type: :command_failed) unless jobs

    cancel_flag = context&.[](:cancel_flag) #: Riffer::Rig::Runtime::CancelFlag?
    wait_seconds = wait_ms / 1000.0
    job, output = await(jobs, job_id, monotonic_now + wait_seconds, cancel_flag)
    return error("No background job #{job_id}", type: :not_found) unless job && output

    cancelled = cancel_flag&.set?
    # Truncated before stripping so skipped output is always marked; scrubbed
    # because a byte offset or cut can split a multibyte character.
    output = truncate(output).scrub.rstrip
    content = "#{output.empty? ? '(no new output)' : output}\n#{state(job, cancelled, wait_seconds)}"

    cancelled || job.status&.nonzero? ? error(content, type: :command_failed) : text(content)
  end

  private

  # @rbs jobs: Riffer::Rig::Tools::Bash::Jobs
  # @rbs job_id: String
  # @rbs deadline: Float
  # @rbs cancel_flag: Riffer::Rig::Runtime::CancelFlag?
  # @rbs return: [Riffer::Rig::Tools::Bash::Job, String]?
  def await(jobs, job_id, deadline, cancel_flag)
    output = +''
    loop do
      polled = jobs.poll(job_id)
      return unless polled

      job, chunk = polled
      output << chunk if output.bytesize <= Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES
      return [job, output] if job.completed? || cancel_flag&.set? || monotonic_now >= deadline

      sleep Riffer::Rig::Tools::Bash::POLL_SECONDS
    end
  end

  # @rbs job: Riffer::Rig::Tools::Bash::Job
  # @rbs cancelled: bool?
  # @rbs wait_seconds: Float
  # @rbs return: String
  def state(job, cancelled, wait_seconds)
    line = job.completed? ? "[exited with status #{job.status}]" : '[running]'
    return "[cancelled]\n#{line}" if cancelled

    job.active? && wait_seconds.positive? ? "[timed out after #{wait_seconds.round}s]\n#{line}" : line
  end
end
