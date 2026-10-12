# frozen_string_literal: true

require 'securerandom'

class Riffer::Rig::Tools::Bash::Jobs
  include Riffer::Rig::Tools::Bash::KillGroup
  include Riffer::Rig::Tools::Bash::MonotonicClock

  READ_LIMIT_BYTES = 2 * Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES #: Integer

  TAIL_BYTES = 2_000 #: Integer

  SHUTDOWN_GRACE_SECONDS = 2.0 #: Float

  # @rbs @inbox: Riffer::Rig::Tools::Bash::_Inbox
  # @rbs @jobs: Hash[String, Riffer::Rig::Tools::Bash::Job]
  # @rbs @mutex: Mutex
  # @rbs @watchers: ThreadGroup

  # @rbs inbox: Riffer::Rig::Tools::Bash::_Inbox
  # @rbs return: void
  def initialize(inbox)
    @inbox = inbox
    @jobs = {}
    @mutex = Mutex.new
    @watchers = ThreadGroup.new
  end

  # @rbs pid: Integer
  # @rbs command: String
  # @rbs output_path: String
  # @rbs return: Riffer::Rig::Tools::Bash::Job
  def register(pid, command, output_path)
    job = Riffer::Rig::Tools::Bash::Job.new(
      id: SecureRandom.hex(4),
      pid: pid,
      command: command,
      output_path: output_path,
      started_at: monotonic_now
    )
    @mutex.synchronize { @jobs[job.id] = job }
    @watchers.add(Thread.new { watch(job) })
    job
  end

  # @rbs return: Array[Riffer::Rig::Tools::Bash::Job]
  def list
    @mutex.synchronize { @jobs.values }
  end

  # @rbs id: String
  # @rbs return: [Riffer::Rig::Tools::Bash::Job, String]?
  def read(id)
    @mutex.synchronize do
      job = @jobs.fetch(id, nil)
      return unless job

      size = File.size(job.output_path)
      output = slice(job.output_path, READ_LIMIT_BYTES, job.offset)
      # Output past the read limit is dropped rather than queued, so a job writing
      # faster than it is read cannot build a backlog; the max covers a file
      # that grew between the size and the read.
      advanced = job.advance([output.bytesize, size - job.offset].max)
      @jobs[id] = advanced
      [advanced, output]
    end
  end

  # @rbs id: String
  # @rbs return: Riffer::Rig::Tools::Bash::Job?
  def kill(id)
    # A completed job's pid is already reaped and may belong to another process.
    @mutex.synchronize { @jobs.fetch(id, nil)&.tap { |job| kill_group(job.pid) if job.active? } }
  end

  # @rbs signal: String
  # @rbs return: void
  def kill_outstanding(signal = 'TERM')
    @mutex.synchronize { @jobs.each_value.select(&:active?).each { |job| kill_group(job.pid, signal) } }
  end

  # @rbs return: Array[Riffer::Rig::Runtime::JobCompletion]
  def consume
    completions = @inbox.drain
    @mutex.synchronize { completions.each { |completion| @jobs.delete(completion.job_id) } }
    completions
  end

  # @rbs grace: Float
  # @rbs return: void
  def shutdown(grace = SHUTDOWN_GRACE_SECONDS)
    kill_outstanding
    deadline = monotonic_now + grace
    @watchers.list.each { |watcher| watcher.join([deadline - monotonic_now, 0.0].max) }
    # A job that ignores TERM would otherwise hold its watcher, and this join, forever.
    kill_outstanding('KILL')
    @watchers.list.each(&:join)
  end

  private

  # @rbs job: Riffer::Rig::Tools::Bash::Job
  # @rbs return: void
  def watch(job)
    # The only reap of a job: a second reaper would take the exit status and
    # leave this wait with ECHILD.
    _pid, status = Process.wait2(job.pid)
    exit_status = status.exitstatus || 1
    finished = @mutex.synchronize { @jobs[job.id] = @jobs.fetch(job.id).finish(exit_status, monotonic_now) }
    @inbox.push(completion(finished, exit_status))
  rescue Errno::ECHILD
    @mutex.synchronize { @jobs.delete(job.id) }
  end

  # @rbs job: Riffer::Rig::Tools::Bash::Job
  # @rbs exit_status: Integer
  # @rbs return: Riffer::Rig::Runtime::JobCompletion
  def completion(job, exit_status)
    path = job.output_path
    Riffer::Rig::Runtime::JobCompletion.new(
      job_id: job.id,
      command: job.command,
      exit_status: exit_status,
      duration: job.elapsed(monotonic_now),
      output_path: path,
      # Scrubbed because the cut can split a multibyte character.
      tail: slice(path, TAIL_BYTES, [File.size(path) - TAIL_BYTES, 0].max).scrub
    )
  end

  # @rbs path: String
  # @rbs limit: Integer
  # @rbs offset: Integer
  # @rbs return: String
  def slice(path, limit, offset)
    read = File.read(path, limit, offset) #: String?
    (read || +'').force_encoding(Encoding.default_external)
  end
end
