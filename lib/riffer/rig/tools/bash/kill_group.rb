# frozen_string_literal: true

module Riffer::Rig::Tools::Bash::KillGroup
  # @rbs pid: Integer
  # @rbs return: Integer
  def kill_group(pid)
    pgid = Process.getpgid(pid)
    Process.kill('TERM', -pgid)
    # A stopped process holds TERM pending until it is continued.
    Process.kill('CONT', -pgid)
    pgid
  rescue Errno::ESRCH, Errno::EPERM
    0
  end
end
