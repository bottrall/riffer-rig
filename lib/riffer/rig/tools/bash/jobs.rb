# frozen_string_literal: true

require 'securerandom'

class Riffer::Rig::Tools::Bash::Jobs
  include Riffer::Rig::Tools::Bash::KillGroup

  # @rbs @jobs: Hash[String, Riffer::Rig::Tools::Bash::Job]
  # @rbs @mutex: Mutex

  # @rbs return: void
  def initialize
    @jobs = {}
    @mutex = Mutex.new
  end

  # @rbs pid: Integer
  # @rbs output_path: String
  # @rbs return: Riffer::Rig::Tools::Bash::Job
  def register(pid, output_path)
    job = Riffer::Rig::Tools::Bash::Job.new(
      id: SecureRandom.hex(4),
      pid: pid,
      output_path: output_path,
      started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC)
    )
    @mutex.synchronize do
      sweep
      @jobs[job.id] = job
    end
    job
  end

  # @rbs return: Array[Riffer::Rig::Tools::Bash::Job]
  def list
    @mutex.synchronize do
      jobs = @jobs.values.filter_map { |job| reap(job) }
      @jobs = jobs.to_h { |job| [job.id, job] }
      sweep
      jobs
    end
  end

  # @rbs return: void
  def kill_outstanding
    @mutex.synchronize do
      @jobs.each_value.select(&:active?).each { |job| kill_group(job.pid) }
    end
  end

  private

  # @rbs job: Riffer::Rig::Tools::Bash::Job
  # @rbs return: Riffer::Rig::Tools::Bash::Job?
  def reap(job)
    return job unless job.active?

    waited = Process.waitpid2(job.pid, Process::WNOHANG) #: [Integer, Process::Status]?
    return job unless waited

    job.finish(waited[1].exitstatus || 1, Process.clock_gettime(Process::CLOCK_MONOTONIC))
  rescue Errno::ECHILD
    nil
  end

  # @rbs return: void
  def sweep
    @jobs.delete_if { |_id, job| job.completed? }
  end
end
