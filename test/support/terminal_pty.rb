# frozen_string_literal: true

require 'pty'
require 'io/console'

class TerminalPty
  TIMEOUT_SECONDS = 5

  def self.drive(script, columns: 80)
    pty = new(columns: columns)
    runner = Thread.current
    returned = Queue.new
    # The terminal keeps the calling thread, where a Ctrl-C's Interrupt is
    # raised.
    typist = Thread.new do
      script.call(pty)
      returned.pop(timeout: TIMEOUT_SECONDS) || raise('the terminal was still running after its script')
    rescue StandardError => e
      # A terminal left waiting for keys would hang the suite, and a turn in
      # flight rescues anything that is a StandardError.
      runner.raise(Minitest::Assertion, e.message)
    end
    begin
      yield pty.slave
      returned << true
      typist.join
    ensure
      typist.kill
      written = pty.close
    end
    written
  end

  attr_reader :slave

  def initialize(columns: 80, rows: 24)
    @master, @slave = PTY.open
    @slave.winsize = [rows, columns]
    @written = +''
    @mutex = Mutex.new
    # Nothing else empties the pty, and a full one would block the writer.
    @reader = Thread.new { read }
  end

  def type(bytes)
    # The key pipeline only sees keys typed once it holds the tty in raw mode.
    wait_until('the tty never went raw') { !@slave.echo? }
    @master.write(bytes)
  end

  def feed(bytes)
    # A blocking read finds a line typed ahead of it in the tty's own buffer.
    @master.write(bytes)
  end

  def await(text, count: 1)
    wait_until("never saw #{text.inspect} #{count} time(s)") { written.scan(text).size >= count }
  end

  def written
    @mutex.synchronize { @written.dup }
  end

  def close
    @slave.close
    @reader.join
    @master.close
    written
  end

  private

  def read
    loop do
      chunk = @master.readpartial(65_536).force_encoding(Encoding::UTF_8)
      @mutex.synchronize { @written << chunk }
    end
  rescue EOFError, Errno::EIO
    nil
  end

  def wait_until(failure)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT_SECONDS
    until yield
      raise failure if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end
end
