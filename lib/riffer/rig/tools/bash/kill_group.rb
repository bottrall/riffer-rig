# frozen_string_literal: true

module Riffer::Rig::Tools::Bash::KillGroup
  # @rbs pid: Integer
  # @rbs signal: String
  # @rbs return: Integer
  def kill_group(pid, signal = 'TERM')
    Process.kill(signal, -Process.getpgid(pid))
    Process.getpgid(pid)
  rescue Errno::ESRCH, Errno::EPERM
    0
  end
end
