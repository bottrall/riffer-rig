# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash::KillGroup do
  def killer
    Object.new.extend(Riffer::Rig::Tools::Bash::KillGroup)
  end

  def with_group
    pid = Process.spawn('sleep 5', pgroup: true)
    yield pid
  ensure
    stop_group(pid)
  end

  def stop_group(pid)
    Process.kill('KILL', -Process.getpgid(pid))
  rescue Errno::ESRCH
    nil
  end

  it "returns the child's process group id" do
    with_group do |pid|
      refute_equal Process.getpgid(Process.pid), killer.kill_group(pid)
    end
  end

  it 'returns a positive process group id' do
    with_group do |pid|
      assert_operator killer.kill_group(pid), :positive?
    end
  end

  it 'returns zero when the group is gone' do
    assert_equal 0, killer.kill_group(-1)
  end
end
