# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash::KillGroup do
  def host
    Class.new { include Riffer::Rig::Tools::Bash::KillGroup }.new
  end

  def spawn_sleeper
    @pid = Process.spawn('sleep 5', pgroup: true)
  end

  def reap(pid)
    Process.kill('KILL', -pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  after do
    reap(@pid) if @pid
  end

  describe '#kill_group' do
    it 'returns the child process group id' do
      spawn_sleeper
      pgid = host.kill_group(@pid)

      assert_equal @pid, pgid
    end

    it 'returns a positive process group id' do
      spawn_sleeper
      pgid = host.kill_group(@pid)

      assert_operator pgid, :positive?
    end

    it 'returns zero when the group is gone' do
      assert_equal 0, host.kill_group(-1)
    end
  end
end
