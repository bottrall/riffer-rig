# frozen_string_literal: true

require 'test_helper'
require 'pty'
require 'io/console'

describe Riffer::Rig::Terminal::KeyPipeline do
  def setup
    @master, @slave = PTY.open
    @echo_before = @slave.echo?
    @pipeline = Riffer::Rig::Terminal::KeyPipeline.new(input: @slave)
    @pipeline.start
    wait_until { !@slave.echo? }
  end

  def teardown
    @pipeline.stop
    @master.close
    @slave.close
  end

  it 'keeps decoding after an idle gap longer than the read timeout' do
    sleep(Riffer::Rig::Terminal::KeyPipeline::IDLE_SECONDS + 0.1)

    @master.write('a')

    assert_equal Riffer::Rig::Terminal::Key.new(:text, 'a'), pop
  end

  it 'decodes typed characters into text key events' do
    @master.write('a')

    assert_equal Riffer::Rig::Terminal::Key.new(:text, 'a'), pop
  end

  it 'decodes a multi-byte escape sequence into one key event' do
    @master.write("\e[B")

    assert_equal Riffer::Rig::Terminal::Key.new(:down), pop
  end

  it 'decodes a bracketed paste into one key event' do
    @master.write("\e[200~pasted text\e[201~")

    assert_equal Riffer::Rig::Terminal::Key.new(:paste, 'pasted text'), pop
  end

  it 'queues Ctrl-C as a key event while raw mode silences SIGINT' do
    @master.write("\u{3}")

    assert_equal Riffer::Rig::Terminal::Key.new(:ctrl_c), pop
  end

  it 'restores the terminal when the reader stops' do
    @pipeline.stop

    assert_equal @echo_before, @slave.echo?
  end

  it 'does not read when the input is not a tty' do
    pipeline = Riffer::Rig::Terminal::KeyPipeline.new(input: StringIO.new)

    pipeline.start

    assert_nil pipeline.keys.pop(timeout: 0.1)
  end

  private

  def pop
    @pipeline.keys.pop(timeout: 5)
  end

  def wait_until
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until yield
      raise 'condition never held' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end
end
