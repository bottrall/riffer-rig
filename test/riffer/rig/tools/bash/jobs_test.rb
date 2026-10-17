# frozen_string_literal: true

require 'shellwords'
require 'test_helper'

describe Riffer::Rig::Tools::Bash::Jobs do
  def setup
    @inbox = Class.new do
      def initialize
        @completions = Queue.new
      end

      def push(completion)
        @completions << completion
      end

      def drain
        Array.new(@completions.size) { @completions.pop }
      end

      def await
        @completions.pop(timeout: 5)
      end
    end.new
    @jobs = Riffer::Rig::Tools::Bash::Jobs.new(@inbox)
    @strays = []
  end

  def teardown
    @jobs.shutdown(0.0)
    @strays.each { |pid| kill_stray(pid) }
  end

  def kill_stray(pid)
    Process.kill('KILL', pid)
  rescue Errno::ESRCH
    nil
  end

  def start(command, output: nil)
    reader, writer = IO.pipe
    script = output ? "printf %s #{output.shellescape}; exec #{command}" : command
    pid = Process.spawn(script, pgroup: true, out: writer, err: %i[child out])
    writer.close
    job = @jobs.register(pid, command, reader)
    sleep 0.01 until File.size(job.output_path) >= output.to_s.bytesize
    job
  end

  def listed(job)
    @jobs.list.find { |candidate| candidate.id == job.id }
  end

  def child_of(job)
    sleep 0.01 until File.size?(job.output_path)
    Integer(File.read(job.output_path)).tap { |pid| @strays << pid }
  end

  def orphan(lifetime = 30)
    job = start("sleep #{lifetime} >/dev/null 2>&1 & echo $!")
    @inbox.await
    child_of(job)
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def eventually
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    sleep 0.01 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    yield
  end

  def exited?(pid)
    eventually { !alive?(pid) }
  end

  describe '#register' do
    it 'registers a job with the spawned pid' do
      pid = Process.spawn('sleep 5', pgroup: true)

      assert_equal pid, @jobs.register(pid, 'sleep 5', File.open(File::NULL)).pid
    end

    it 'registers a job with the given command' do
      assert_equal 'sleep 5', start('sleep 5').command
    end

    it 'registers a job with an output path in a directory private to its owner' do
      job = start('sleep 5')

      assert_equal 0o700, File.stat(File.dirname(job.output_path)).mode & 0o777
    end

    it 'keeps the output of every job in one directory' do
      assert_equal File.dirname(start('sleep 5').output_path), File.dirname(start('sleep 5').output_path)
    end

    it 'registers a job after the output directory was removed' do
      FileUtils.remove_entry(File.dirname(start('sleep 5').output_path))

      assert_path_exists start('sleep 5').output_path
    end

    it 'registers a job as active' do
      assert_predicate start('sleep 5'), :active?
    end

    it 'keys each job by a distinct id' do
      refute_equal start('sleep 5').id, start('sleep 5').id
    end
  end

  describe '#list' do
    it 'lists the registered jobs' do
      job = start('sleep 5')

      assert_equal [job.id], @jobs.list.map(&:id)
    end

    it 'keeps a finished job until its completion is consumed' do
      job = start('true')
      @inbox.await

      assert_predicate listed(job), :completed?
    end
  end

  describe '#read' do
    it 'reads an unknown job as nil' do
      assert_nil @jobs.read('missing1')
    end

    it 'reads the output a job has written' do
      job = start('echo hello')
      @inbox.await

      assert_equal "hello\n", @jobs.read(job.id)&.last
    end

    it 'reads only the output written since the last read' do
      job = start('sleep 5', output: 'first')
      @jobs.read(job.id)
      File.write(job.output_path, 'second', mode: 'a')

      assert_equal 'second', @jobs.read(job.id)&.last
    end

    it 'reads no more than the read limit at once' do
      limit = Riffer::Rig::Tools::Bash::Jobs::READ_LIMIT_BYTES
      job = start('sleep 5', output: "#{'a' * limit}skipped")

      assert_equal 'a' * limit, @jobs.read(job.id)&.last
    end

    it 'skips the output beyond the read limit on the next read' do
      job = start('sleep 5', output: 'a' * (Riffer::Rig::Tools::Bash::Jobs::READ_LIMIT_BYTES + 7))
      @jobs.read(job.id)
      File.write(job.output_path, 'tail', mode: 'a')

      assert_equal 'tail', @jobs.read(job.id)&.last
    end

    it 'reads nothing new as an empty string' do
      job = start('sleep 5')

      assert_equal '', @jobs.read(job.id)&.last
    end

    it 'returns the job advanced past what it read' do
      job = start('sleep 5', output: 'hello')

      assert_equal 5, @jobs.read(job.id)&.first&.offset
    end

    it 'keeps the offset of a job that finishes after a read' do
      job = start('sleep 0.2', output: 'hello')
      @jobs.read(job.id)
      @inbox.await

      assert_equal 5, listed(job).offset
    end
  end

  describe '#kill' do
    it 'kills an unknown job as nil' do
      assert_nil @jobs.kill('missing1')
    end

    it 'kills the job' do
      job = start('sleep 30')
      @jobs.kill(job.id)

      assert_equal job.id, @inbox.await&.job_id
    end

    it 'returns the job it killed' do
      job = start('sleep 30')

      assert_equal job.id, @jobs.kill(job.id)&.id
    end

    it 'returns a completed job' do
      job = start('true')
      @inbox.await

      assert_predicate @jobs.kill(job.id), :completed?
    end
  end

  describe '#consume' do
    it 'returns the completions in the inbox' do
      job = start('true')
      @jobs.shutdown

      assert_equal [job.id], @jobs.consume.map(&:job_id)
    end

    it 'drops the consumed jobs from the registry' do
      start('true')
      @jobs.shutdown
      @jobs.consume

      assert_empty @jobs.list
    end

    it 'keeps the jobs still running' do
      job = start('sleep 30')
      @jobs.consume

      assert_equal [job.id], @jobs.list.map(&:id)
    end
  end

  describe '#shutdown' do
    it 'kills every active job' do
      jobs = Array.new(2) { start('sleep 30') }
      @jobs.shutdown

      assert_equal([true, true], jobs.map { |job| listed(job).completed? })
    end

    it 'kills a group that outlived its leader' do
      pid = orphan
      @jobs.shutdown

      assert exited?(pid)
    end

    it 'kills a group that outlived its leader after the job is consumed' do
      job = start('sleep 30 & echo $!')
      @inbox.push(@inbox.await)
      pid = child_of(job)
      @jobs.consume
      @jobs.shutdown

      assert exited?(pid)
    end

    it 'lets a group that outlived its leader exit on TERM' do
      Dir.mktmpdir do |dir|
        job = start("(trap 'touch #{dir}/termed; exit' TERM; echo ready; sleep 5; :) &")
        sleep 0.01 until File.size?(job.output_path)
        @inbox.await
        @jobs.shutdown

        assert_path_exists File.join(dir, 'termed')
      end
    end

    it 'lets a stopped job exit on TERM' do
      Dir.mktmpdir do |dir|
        job = start("trap 'touch #{dir}/termed; exit' TERM; echo ready; sleep 30")
        sleep 0.01 until File.size?(job.output_path)
        Process.kill('STOP', -job.pid)
        sleep 0.01 until `ps -o stat= -p #{job.pid}`.start_with?('T')
        @jobs.shutdown

        assert_path_exists File.join(dir, 'termed')
      end
    end

    it 'kills a job that ignores TERM' do
      job = start('trap "" TERM; echo ready; sleep 30')
      sleep 0.01 until File.size?(job.output_path)
      @jobs.shutdown(0.1)

      assert_predicate listed(job), :completed?
    end

    it 'kills a group that ignores TERM after TERM ends its leader' do
      pid = child_of(start('trap "" TERM; sleep 30 & trap - TERM; echo $!; wait'))
      @jobs.shutdown(0.1)

      assert exited?(pid)
    end

    it 'returns while a killed group still holds an unreaped process' do
      job = start('sleep 30')
      unreaped = Process.spawn('true', pgroup: job.pid)

      assert Thread.new { @jobs.shutdown(0.0) }.join(5)
    ensure
      Process.wait(unreaped)
    end

    it 'leaves no watcher thread' do
      threads = Thread.list
      start('sleep 30')
      @jobs.shutdown

      assert_empty Thread.list - threads
    end

    it 'leaves no zombie process' do
      job = start('sleep 30')
      @jobs.shutdown

      assert_raises(Errno::ECHILD) { Process.wait(job.pid) }
    end

    it 'leaves no thread copying output that is still held open' do
      threads = Thread.list
      reader, writer = IO.pipe
      @jobs.register(Process.spawn('true', pgroup: true), 'true', reader)
      @jobs.shutdown
      writer.close

      assert_empty Thread.list - threads
    end

    it 'removes the output of its jobs' do
      job = start('sleep 30')
      @jobs.shutdown

      refute_path_exists File.dirname(job.output_path)
    end

    it 'removes the output of a job whose completion was consumed' do
      job = start('true')
      @inbox.await
      @jobs.consume
      @jobs.shutdown

      refute_path_exists File.dirname(job.output_path)
    end

    it 'shuts down a registry that ran no job' do
      @jobs.shutdown

      assert_empty @jobs.list
    end
  end

  describe 'watcher' do
    it 'records a zero exit without a registry read' do
      start('true')

      assert_equal 0, @inbox.await&.exit_status
    end

    it 'records a non-zero exit' do
      start('exit 3')

      assert_equal 3, @inbox.await&.exit_status
    end

    it 'records no exit status for a job ended by a signal' do
      job = start('sleep 30')
      Process.kill('KILL', job.pid)

      assert_nil @inbox.await&.exit_status
    end

    it 'records the signal that ended a job' do
      job = start('sleep 30')
      @jobs.kill(job.id)

      assert_equal 'TERM', @inbox.await&.signal
    end

    it 'records no signal for a job that exited' do
      start('exit 3')

      assert_nil @inbox.await&.signal
    end

    it 'records a job ended by a signal as completed on the registry' do
      job = start('sleep 30')
      @jobs.kill(job.id)
      @inbox.await

      assert_predicate listed(job), :completed?
    end

    it 'puts one completion in the inbox per job' do
      start('true')
      @jobs.shutdown

      assert_equal 1, @inbox.drain.size
    end

    it 'completes a job with its id' do
      job = start('true')

      assert_equal job.id, @inbox.await&.job_id
    end

    it 'completes a job with its command' do
      start('exit 0')

      assert_equal 'exit 0', @inbox.await&.command
    end

    it 'completes a job with its duration' do
      start('sleep 0.3')

      assert_operator @inbox.await&.duration, :>=, 0.2
    end

    it 'leaves the wait for held-open output out of the duration' do
      start('sleep 30 & echo started')

      assert_operator @inbox.await&.duration, :<, Riffer::Rig::Tools::Bash::Jobs::DRAIN_SECONDS
    end

    it 'completes a job with its output path' do
      job = start('true')

      assert_equal job.output_path, @inbox.await&.output_path
    end

    it 'completes a job with the tail of its output' do
      tail = 'b' * Riffer::Rig::Tools::Bash::Jobs::TAIL_BYTES
      start('true', output: "aaa#{tail}")

      assert_equal tail, @inbox.await&.tail
    end

    it 'completes a job that wrote nothing with an empty tail' do
      start('true')

      assert_equal '', @inbox.await&.tail
    end

    it 'completes a job with output that arrives after its process was reaped' do
      reader, writer = IO.pipe
      pid = Process.spawn('true', pgroup: true)
      @jobs.register(pid, 'true', reader)
      sleep 0.01 while alive?(pid)
      writer.write('late')
      writer.close

      assert_equal 'late', @inbox.await&.tail
    end

    it 'completes a job that left a process holding its output open' do
      start('sleep 30 & echo started')

      assert_equal "started\n", @inbox.await&.tail
    end

    it 'scrubs a multibyte character split by the tail cut' do
      start('true', output: "é#{'b' * (Riffer::Rig::Tools::Bash::Jobs::TAIL_BYTES - 1)}")

      assert_predicate @inbox.await&.tail, :valid_encoding?
    end

    it 'keeps watching a group that outlived its leader' do
      threads = Thread.list
      orphan

      assert_equal 1, (Thread.list - threads).size
    end

    it 'stops watching a group once it is empty' do
      threads = Thread.list
      orphan(0.2)
      eventually { (Thread.list - threads).empty? }

      assert_empty Thread.list - threads
    end

    it 'drops a job whose process can no longer be waited on' do
      pid = Process.spawn('true')
      Process.wait(pid)
      @jobs.register(pid, 'true', File.open(File::NULL))
      @jobs.shutdown

      assert_empty @jobs.list
    end
  end
end
