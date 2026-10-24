# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require 'tmpdir'

class Riffer::Rig::Runtime::Jobs
  TAIL_BYTES = 2_000 #: Integer

  SHUTDOWN_GRACE_SECONDS = 2.0 #: Float

  DRAIN_SECONDS = 0.5 #: Float

  POLL_SECONDS = 0.1 #: Float

  # @rbs @inbox: Riffer::Rig::Runtime::JobInbox
  # @rbs @jobs: Hash[String, Riffer::Rig::Runtime::Job]
  # @rbs @groups: Array[Integer]
  # @rbs @logs: Hash[String, Riffer::Rig::Runtime::JobLog]
  # @rbs @directory: String?
  # @rbs @mutex: Mutex
  # @rbs @watchers: ThreadGroup
  # @rbs @clock: ^() -> Float

  # @rbs inbox: Riffer::Rig::Runtime::JobInbox
  # @rbs clock: ^() -> Float
  # @rbs return: void
  def initialize(inbox, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @inbox = inbox
    @clock = clock
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
  # @rbs return: Riffer::Rig::Runtime::Job
  def register(pid, command, output)
    id = SecureRandom.hex(4)
    path = File.join(directory, id)
    log = Riffer::Rig::Runtime::JobLog.new(output, path)
    job = Riffer::Rig::Runtime::Job.new(
      id: id,
      pid: pid,
      command: command,
      output_path: path,
      started_at: @clock.call
    )
    @mutex.synchronize do
      @jobs[id] = job
      @groups << pid
      @logs[id] = log
    end
    @watchers.add(Thread.new { watch(job, log) })
    job
  end

  # @rbs return: Array[Riffer::Rig::Runtime::Job]
  def list
    @mutex.synchronize { @jobs.values }
  end

  # @rbs id: String
  # @rbs limit: Integer
  # @rbs return: [Riffer::Rig::Runtime::Job, String]?
  def read(id, limit)
    @mutex.synchronize do
      job = @jobs.fetch(id, nil)
      return unless job

      output, written = @logs.fetch(id).read(job.offset, limit)
      # Output past the read limit is dropped rather than queued, so a job writing
      # faster than it is read cannot build a backlog.
      advanced = job.advance(written - job.offset)
      @jobs[id] = advanced
      [advanced, output]
    end
  end

  # @rbs id: String
  # @rbs return: Riffer::Rig::Runtime::Job?
  def kill(id)
    @mutex.synchronize do
      @jobs.fetch(id, nil)&.tap do |job|
        # A completed job's pid is already reaped and may belong to another process.
        next unless job.active?

        signal_group(job.pid, 'TERM')
        # A stopped process holds TERM pending until it is continued.
        signal_group(job.pid, 'CONT')
      end
    end
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
    kill_outstanding('TERM')
    # A stopped process holds TERM pending until it is continued.
    kill_outstanding('CONT')
    deadline = @clock.call + grace
    @watchers.list.each { |watcher| watcher.join([deadline - @clock.call, 0.0].max) }
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

  # @rbs job: Riffer::Rig::Runtime::Job
  # @rbs log: Riffer::Rig::Runtime::JobLog
  # @rbs return: void
  def watch(job, log)
    # The only reap of a job: a second reaper would take the exit status and
    # leave this wait with ECHILD.
    _pid, status = Process.wait2(job.pid)
    # Once reaped, the leader's pid is reserved only while its group has
    # members. An emptied group is forgotten before the number can name one
    # that is not ours: here, ahead of the subscribers, and by the poll below.
    retain(job.pid)
    finished = @mutex.synchronize { @jobs[job.id] = @jobs.fetch(job.id).finish(@clock.call) }
    # Bounded because a process the job left behind can hold the pipe open
    # long after the job itself has exited.
    log.drain(DRAIN_SECONDS)
    @inbox.push(completion(finished, log, status))
    sleep(POLL_SECONDS) while retain(job.pid)
  rescue Errno::ECHILD
    @mutex.synchronize do
      @jobs.delete(job.id)
      @groups.delete(job.pid)
    end
  end

  # @rbs signal: String
  # @rbs return: void
  def kill_outstanding(signal)
    @mutex.synchronize { @groups.each { |pgid| signal_group(pgid, signal) } }
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

  # @rbs job: Riffer::Rig::Runtime::Job
  # @rbs log: Riffer::Rig::Runtime::JobLog
  # @rbs status: Process::Status
  # @rbs return: Riffer::Rig::Runtime::JobCompletion
  def completion(job, log, status)
    Riffer::Rig::Runtime::JobCompletion.new(
      job_id: job.id,
      command: job.command,
      exit_status: status.exitstatus,
      signal: status.termsig&.then { |number| Signal.signame(number) },
      duration: job.elapsed(@clock.call),
      output_path: job.output_path,
      # Scrubbed because the cut can split a multibyte character.
      tail: log.tail(TAIL_BYTES).scrub
    )
  end
end
