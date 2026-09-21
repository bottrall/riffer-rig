# frozen_string_literal: true

require 'open3'

class Riffer::Rig::Tools::Bash < Riffer::Tool
  identifier 'bash'
  description 'Run a shell command in the working directory and return its combined stdout/stderr and exit status. ' \
              'Use this for listing, searching (rg/grep/find), running tests, git, etc.'

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
  end

  # @rbs context: Riffer::Agent::Context?
  # @rbs command: String
  # @rbs timeout_ms: Integer
  # @rbs return: Riffer::Tools::Response
  def call(context:, command:, timeout_ms: DEFAULT_TIMEOUT_MS)
    cancel_flag = context&.[](:cancel_flag) #: Riffer::Rig::Runtime::CancelFlag?
    output, status = run(command, timeout_ms / 1000.0, cancel_flag)
    output = truncate(output.rstrip)

    return error("Command exited with status #{status}\n#{output}", type: :command_failed) unless status.zero?

    text(output.empty? ? '(no output)' : output)
  end

  private

  # @rbs command: String
  # @rbs timeout_seconds: Float
  # @rbs cancel_flag: Riffer::Rig::Runtime::CancelFlag?
  # @rbs return: [String, Integer]
  def run(command, timeout_seconds, cancel_flag)
    stdin, stdout_and_stderr, wait_thread = Open3.popen2e(command, chdir: Dir.pwd, pgroup: true)
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

  # @rbs pid: Integer
  # @rbs return: Integer
  def kill_group(pid)
    Process.kill('TERM', -Process.getpgid(pid))
    Process.getpgid(pid)
  rescue Errno::ESRCH, Errno::EPERM
    0
  end

  # @rbs output: String
  # @rbs return: String
  def truncate(output)
    return output if output.bytesize <= MAX_OUTPUT_BYTES

    "#{output.byteslice(0, MAX_OUTPUT_BYTES)}\n[output truncated to #{MAX_OUTPUT_BYTES} bytes]"
  end
end
