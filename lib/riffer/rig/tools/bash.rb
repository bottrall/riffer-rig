# frozen_string_literal: true

require 'open3'
require 'securerandom'
require 'tmpdir'

class Riffer::Rig::Tools::Bash < Riffer::Tool
  include Riffer::Rig::Tools::Bash::KillGroup

  identifier 'bash'
  description 'Run a shell command in the working directory and return its combined stdout/stderr and exit status. ' \
              'Use this for exploring and running things: ls, rg or grep, find, tests, git, package managers.'

  timeout 600

  DEFAULT_TIMEOUT_MS = 120_000 #: Integer

  MAX_OUTPUT_BYTES = 30_000 #: Integer

  POLL_SECONDS = 0.1 #: Float

  params do
    required :command, String, description: 'The shell command to run'
    optional :timeout_ms,
             Integer,
             description: 'Kill the command after this many milliseconds',
             default: DEFAULT_TIMEOUT_MS
    optional :run_in_background,
             Riffer::Params::Boolean,
             description: 'Start the command in the background and return a job id and output path immediately',
             default: false
  end

  # @rbs context: Riffer::Agent::Context?
  # @rbs command: String
  # @rbs timeout_ms: Integer
  # @rbs run_in_background: bool
  # @rbs return: Riffer::Tools::Response
  def call(context:, command:, timeout_ms: DEFAULT_TIMEOUT_MS, run_in_background: false)
    return spawn_job(context, command) if run_in_background

    cancel_flag = context&.[](:cancel_flag) #: Riffer::Rig::Runtime::CancelFlag?
    cwd = context&.[](:cwd) #: String
    output, status = run(command, cwd, timeout_ms / 1000.0, cancel_flag)
    output = truncate(output.rstrip)

    return error("Command exited with status #{status}\n#{output}", type: :command_failed) unless status.zero?

    text(output.empty? ? '(no output)' : output)
  end

  private

  # @rbs context: Riffer::Agent::Context?
  # @rbs command: String
  # @rbs return: Riffer::Tools::Response
  def spawn_job(context, command)
    jobs = context&.[](:jobs) #: Riffer::Rig::Tools::Bash::Jobs?
    return error('no background job registry in the context', type: :command_failed) unless jobs

    cwd = context&.[](:cwd) #: String
    path = File.join(Dir.tmpdir, "riffer-rig-job-#{SecureRandom.hex(4)}")
    pid = Process.spawn(command, chdir: cwd, pgroup: true, out: [path, 'w', 0o600], err: %i[child out])
    job = jobs.register(pid, path)

    text("Job #{job.id} started in background\nOutput: #{job.output_path}")
  end

  # @rbs command: String
  # @rbs cwd: String
  # @rbs timeout_seconds: Float
  # @rbs cancel_flag: Riffer::Rig::Runtime::CancelFlag?
  # @rbs return: [String, Integer]
  def run(command, cwd, timeout_seconds, cancel_flag)
    stdin, stdout_and_stderr, wait_thread = Open3.popen2e(command, chdir: cwd, pgroup: true)
    stdin.close

    ending = await(wait_thread, monotonic_now + timeout_seconds, cancel_flag)
    kill_group(wait_thread.pid) unless ending == :exited
    output = stdout_and_stderr.read
    stdout_and_stderr.close

    case ending
    when :timed_out then ["#{output}\n[timed out after #{timeout_seconds.round}s]", 124]
    when :cancelled then ["#{output}\n[cancelled]", 130]
    else [output, wait_thread.value.exitstatus || 1]
    end
  end

  # @rbs wait_thread: Process::Waiter
  # @rbs deadline: Float
  # @rbs cancel_flag: Riffer::Rig::Runtime::CancelFlag?
  # @rbs return: Symbol
  def await(wait_thread, deadline, cancel_flag)
    # Upstream candidate: a cancel token on riffer's run loop would reach a
    # running tool directly; until then the flag is polled from the context.
    until wait_thread.join(POLL_SECONDS)
      return :cancelled if cancel_flag&.set?
      return :timed_out if monotonic_now >= deadline
    end
    :exited
  end

  # @rbs return: Float
  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # @rbs output: String
  # @rbs return: String
  def truncate(output)
    return output if output.bytesize <= MAX_OUTPUT_BYTES

    "#{output.byteslice(0, MAX_OUTPUT_BYTES)}\n[output truncated to #{MAX_OUTPUT_BYTES} bytes]"
  end
end
