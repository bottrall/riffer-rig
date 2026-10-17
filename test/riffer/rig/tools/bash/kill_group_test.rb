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

    it 'sends TERM' do
      spawn_sleeper
      host.kill_group(@pid)

      assert_equal Signal.list.fetch('TERM'), Process.wait2(@pid).last.termsig
    end

    it 'delivers TERM to a stopped child' do
      spawn_sleeper
      Process.kill('STOP', @pid)
      Process.wait2(@pid, Process::WUNTRACED)
      host.kill_group(@pid)

      assert_equal Signal.list.fetch('TERM'), Process.detach(@pid).join(5)&.value&.termsig
    end

    it 'signals the processes the child started' do
      IO.pipe do |reader, writer|
        @pid = Process.spawn('sleep 30 & echo started; wait', pgroup: true, out: writer)
        writer.close
        reader.gets
        host.kill_group(@pid)

        # The pipe reaches end of file only once every process holding its write
        # end has exited, the backgrounded sleep included.
        assert reader.wait_readable(5)
      end
    end

    it 'returns zero when the group is gone' do
      assert_equal 0, host.kill_group(-1)
    end
  end
end
