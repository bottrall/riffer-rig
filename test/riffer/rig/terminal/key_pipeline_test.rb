# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/key_pty'

describe Riffer::Rig::Terminal::KeyPipeline do
  def setup
    @pty = KeyPty.new
  end

  def teardown
    @pty.close
  end

  it 'keeps decoding after an idle gap longer than the read timeout' do
    sleep(Riffer::Rig::Terminal::KeyPipeline::IDLE_SECONDS + 0.1)

    @pty.type('a')

    assert_equal Riffer::Rig::Terminal::Key.new(:text, 'a'), @pty.key
  end

  it 'decodes typed characters into text key events' do
    @pty.type('a')

    assert_equal Riffer::Rig::Terminal::Key.new(:text, 'a'), @pty.key
  end

  it 'decodes a multi-byte escape sequence into one key event' do
    @pty.type("\e[B")

    assert_equal Riffer::Rig::Terminal::Key.new(:down), @pty.key
  end

  it 'decodes a bracketed paste into one key event' do
    @pty.type("\e[200~pasted text\e[201~")

    assert_equal Riffer::Rig::Terminal::Key.new(:paste, 'pasted text'), @pty.key
  end

  it 'queues Ctrl-C as a key event while raw mode silences SIGINT' do
    @pty.type("\u{3}")

    assert_equal Riffer::Rig::Terminal::Key.new(:ctrl_c), @pty.key
  end

  it 'restores the terminal when the reader stops' do
    @pty.pipeline.stop

    assert_predicate @pty.slave, :echo?
  end

  it 'does not read when the input is not a tty' do
    pipeline = Riffer::Rig::Terminal::KeyPipeline.new(input: StringIO.new)

    pipeline.start

    assert_nil pipeline.keys.pop(timeout: 0.1)
  end
end
