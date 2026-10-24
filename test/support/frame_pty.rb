# frozen_string_literal: true

require 'pty'
require 'io/console'
require_relative 'screen'

class FramePty
  TIMEOUT_SECONDS = 5

  attr_reader :slave

  def initialize(columns:, rows:)
    @rows = rows
    @master, @slave = PTY.open
    # The key pipeline holds the terminal in raw mode whenever a footer is up.
    @slave.raw!
    @slave.winsize = [rows, columns]
    @screen = Screen.new(rows: rows, columns: columns)
    @transcript = +''
    @mutex = Mutex.new
    @stopped = false
    # Nothing else empties the pty, and a write blocked on a full one holds
    # the frame's lock.
    @reader = Thread.new { read }
  end

  def screen
    @mutex.synchronize do
      drain
      @screen
    end
  end

  def transcript
    @mutex.synchronize do
      drain
      @transcript.dup
    end
  end

  def resize(columns)
    @mutex.synchronize do
      drain
      @screen.columns = columns
    end
    report(columns)
  end

  # Nothing holds this pty as its controlling terminal, so the kernel has no
  # process to signal about the new size.
  def report(columns, rows: @rows)
    before = transcript.bytesize
    @slave.winsize = [rows, columns]
    Process.kill('WINCH', Process.pid)
    wait_until("no redraw within #{TIMEOUT_SECONDS}s") { transcript.bytesize > before }
  end

  def close
    @stopped = true
    @reader.join
    @master.close
    @slave.close
  end

  private

  def read
    until @stopped
      @master.wait_readable(0.01)
      @mutex.synchronize { drain }
    end
  end

  def drain
    while @master.wait_readable(0)
      bytes = @master.read_nonblock(65_536).force_encoding(Encoding::UTF_8)
      @transcript << bytes
      @screen.write(bytes)
    end
  end

  def wait_until(failure)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT_SECONDS
    until yield
      raise failure if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end
end
