# frozen_string_literal: true

module Riffer::Rig::Tools::Bash::KillGroup
  # @rbs pid: Integer
  # @rbs return: Integer
  def kill_group(pid)
    Process.kill('TERM', -Process.getpgid(pid))
    Process.getpgid(pid)
  rescue Errno::ESRCH, Errno::EPERM
    0
  end
end
