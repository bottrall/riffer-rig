# frozen_string_literal: true

require 'pty'
require 'io/console'

class KeyPty
  TIMEOUT_SECONDS = 5

  attr_reader :slave, :pipeline

  def initialize
    @master, @slave = PTY.open
    @master.timeout = TIMEOUT_SECONDS
    @printed = 0
    @pipeline = Riffer::Rig::Terminal::KeyPipeline.new(input: @slave)
    @pipeline.start
    # Bytes typed before the reader switches the tty to raw mode would be
    # echoed and line-buffered instead of reaching the decoder one by one.
    wait_until { !@slave.echo? }
  end

  def type(bytes)
    @master.write(bytes)
  end

  def key
    @pipeline.keys.pop(timeout: TIMEOUT_SECONDS) || raise("no key within #{TIMEOUT_SECONDS}s")
  end

  def keys_until(name)
    Enumerator.produce { key }.lazy.take_while { |key| key.name != name }
  end

  def print(output)
    @printed += @slave.write(output)
  end

  def output
    @master.read(@printed).tap { @printed = 0 }
  end

  def close
    @pipeline.stop
    @master.close
    @slave.close
  end

  private

  def wait_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT_SECONDS
    until yield
      raise 'condition never held' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end
end
