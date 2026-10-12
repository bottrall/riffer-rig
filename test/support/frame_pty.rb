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
  end

  def screen
    @screen.write(@master.read_nonblock(65_536).force_encoding(Encoding::UTF_8)) while @master.wait_readable(0)
    @screen
  end

  def resize(columns)
    screen.columns = columns
    report(columns)
  end

  # Nothing holds this pty as its controlling terminal, so the kernel has no
  # process to signal about the new size.
  def report(columns)
    screen
    @slave.winsize = [@rows, columns]
    Process.kill('WINCH', Process.pid)
    @master.wait_readable(TIMEOUT_SECONDS) || raise("no redraw within #{TIMEOUT_SECONDS}s")
  end

  def close
    @master.close
    @slave.close
  end
end
