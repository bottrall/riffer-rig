# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require 'tmpdir'

class Riffer::Rig::Tools::Bash::Jobs
  include Riffer::Rig::Tools::Bash::KillGroup
  include Riffer::Rig::Tools::Bash::MonotonicClock

  READ_LIMIT_BYTES = 2 * Riffer::Rig::Tools::Bash::MAX_OUTPUT_BYTES #: Integer

  TAIL_BYTES = 2_000 #: Integer

  SHUTDOWN_GRACE_SECONDS = 2.0 #: Float

  DRAIN_SECONDS = 0.5 #: Float

  # @rbs @inbox: Riffer::Rig::Tools::Bash::_Inbox
  # @rbs @jobs: Hash[String, Riffer::Rig::Tools::Bash::Job]
  # @rbs @groups: Array[Integer]
  # @rbs @logs: Hash[String, Riffer::Rig::Tools::Bash::JobLog]
  # @rbs @directory: String?
  # @rbs @mutex: Mutex
  # @rbs @watchers: ThreadGroup

  # @rbs inbox: Riffer::Rig::Tools::Bash::_Inbox
  # @rbs return: void
  def initialize(inbox)
    @inbox = inbox
    @jobs = {}
    @groups = []
    @logs = {}
    @directory = nil
    @mutex = Mutex.new
    @watchers = ThreadGroup.new
  end

  # @rbs pid: Integer
  # @rbs command: String
  # @rbs output: IO
  # @rbs return: Riffer::Rig::Tools::Bash::Job
  def register(pid, command, output)
    id = SecureRandom.hex(4)
    path = File.join(directory, id)
    log = Riffer::Rig::Tools::Bash::JobLog.new(output, path)
    job = Riffer::Rig::Tools::Bash::Job.new(
      id: id,
      pid: pid,
      command: command,
      output_path: path,
      started_at: monotonic_now
    )
    @mutex.synchronize do
      @jobs[id] = job
      @groups << pid
      @logs[id] = log
    end
    @watchers.add(Thread.new { watch(job, log) })
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

      output, written = @logs.fetch(id).read(job.offset, READ_LIMIT_BYTES)
      # Output past the read limit is dropped rather than queued, so a job writing
      # faster than it is read cannot build a backlog.
      advanced = job.advance(written - job.offset)
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
    @mutex.synchronize { @groups.each { |pgid| signal_group(pgid, signal) } }
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
    # A killed process stays in its group until its parent reaps it. Once the
    # leader is gone that parent is not this process and may never do so, so
    # the watchers are released rather than left polling.
    @mutex.synchronize { @groups.clear }
    @watchers.list.each(&:join)
    logs, directory = @mutex.synchronize { [@logs.values, @directory] }
    # A process that left its job's group can hold the pipe open indefinitely.
    logs.each(&:close)
    FileUtils.rm_rf(directory) if directory
  end

  private

  # @rbs return: String
  def directory
    @mutex.synchronize do
      current = @directory
      # A tmp cleaner or a job can remove the directory between two jobs.
      next current if current && File.directory?(current)

      @directory = Dir.mktmpdir('riffer-rig-jobs-')
    end
  end

  # @rbs job: Riffer::Rig::Tools::Bash::Job
  # @rbs log: Riffer::Rig::Tools::Bash::JobLog
  # @rbs return: void
  def watch(job, log)
    # The only reap of a job: a second reaper would take the exit status and
    # leave this wait with ECHILD.
    _pid, status = Process.wait2(job.pid)
    # Once reaped, the leader's pid is reserved only while its group has
    # members. An emptied group is forgotten before the number can name one
    # that is not ours: here, ahead of the subscribers, and by the poll below.
    retain(job.pid)
    exit_status = status.exitstatus || 1
    finished = @mutex.synchronize { @jobs[job.id] = @jobs.fetch(job.id).finish(exit_status, monotonic_now) }
    # Bounded because a process the job left behind can hold the pipe open
    # long after the job itself has exited.
    log.drain(DRAIN_SECONDS)
    @inbox.push(completion(finished, log, exit_status))
    sleep(Riffer::Rig::Tools::Bash::POLL_SECONDS) while retain(job.pid)
  rescue Errno::ECHILD
    @mutex.synchronize do
      @jobs.delete(job.id)
      @groups.delete(job.pid)
    end
  end

  # @rbs pgid: Integer
  # @rbs return: bool
  def retain(pgid)
    @mutex.synchronize do
      @groups.delete(pgid) unless signal_group(pgid, 0)
      @groups.include?(pgid)
    end
  end

  # @rbs pgid: Integer
  # @rbs signal: String | Integer
  # @rbs return: bool
  def signal_group(pgid, signal)
    Process.kill(signal, -pgid)
    true
  rescue Errno::ESRCH, Errno::EPERM
    false
  end

  # @rbs job: Riffer::Rig::Tools::Bash::Job
  # @rbs log: Riffer::Rig::Tools::Bash::JobLog
  # @rbs exit_status: Integer
  # @rbs return: Riffer::Rig::Runtime::JobCompletion
  def completion(job, log, exit_status)
    Riffer::Rig::Runtime::JobCompletion.new(
      job_id: job.id,
      command: job.command,
      exit_status: exit_status,
      duration: job.elapsed(monotonic_now),
      output_path: job.output_path,
      # Scrubbed because the cut can split a multibyte character.
      tail: log.tail(TAIL_BYTES).scrub
    )
  end
end
