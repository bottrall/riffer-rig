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

  def scripted_input(ready: [], chars: [])
    Class.new do
      attr_reader :reads

      def initialize(ready, chars)
        @ready = ready.dup
        @chars = chars.dup
        @reads = Queue.new
      end

      def tty? = true

      def raw = yield(self)

      def wait_readable(_seconds)
        @ready.empty? || @ready.shift
      end

      def getc
        @reads << :read
        @chars.shift
      end
    end.new(ready, chars)
  end

  describe '#start' do
    it 'does not read when the input is not a tty' do
      pipeline = Riffer::Rig::Terminal::KeyPipeline.new(input: StringIO.new, output: StringIO.new)

      pipeline.start

      assert_nil pipeline.keys.pop(timeout: 0.1)
    end

    it 'leaves bracketed paste alone when the input is not a tty' do
      output = StringIO.new

      Riffer::Rig::Terminal::KeyPipeline.new(input: StringIO.new, output: output).start

      assert_empty output.string
    end

    it 'turns bracketed paste on' do
      assert_equal "\e[?2004h", @pty.written
    end
  end

  describe '#stop' do
    it 'does nothing when the reader was never started' do
      pipeline = Riffer::Rig::Terminal::KeyPipeline.new(input: StringIO.new, output: StringIO.new)

      assert_nil pipeline.stop
    end

    it 'restores the terminal when the reader stops' do
      @pty.pipeline.stop

      assert_predicate @pty.slave, :echo?
    end

    it 'turns bracketed paste off' do
      @pty.pipeline.stop

      assert_equal "\e[?2004h\e[?2004l", @pty.written
    end
  end

  describe '#read_loop' do
    it 'keeps decoding after an idle gap longer than the read timeout' do
      input = scripted_input(ready: [false], chars: ['a'])
      pipeline = Riffer::Rig::Terminal::KeyPipeline.new(input: input, output: StringIO.new)

      pipeline.start
      key = pipeline.keys.pop(timeout: KeyPty::TIMEOUT_SECONDS)
      pipeline.stop

      assert_equal Riffer::Rig::Terminal::Key.new(:text, 'a'), key
    end

    it 'stops reading at end of input' do
      input = scripted_input
      pipeline = Riffer::Rig::Terminal::KeyPipeline.new(input: input, output: StringIO.new)

      pipeline.start
      input.reads.pop(timeout: KeyPty::TIMEOUT_SECONDS)
      pipeline.stop

      assert_empty input.reads
    end

    it 'decodes typed characters into text key events' do
      @pty.type('a')

      assert_equal Riffer::Rig::Terminal::Key.new(:text, 'a'), @pty.key
    end

    it 'queues Ctrl-C as a key event while raw mode silences SIGINT' do
      @pty.type("\u{3}")

      assert_equal Riffer::Rig::Terminal::Key.new(:ctrl_c), @pty.key
    end

    it 'decodes a multi-byte escape sequence into one key event' do
      @pty.type("\e[B")

      assert_equal Riffer::Rig::Terminal::Key.new(:down), @pty.key
    end

    it 'emits a lone escape once the reader gives up waiting for a sequence' do
      @pty.type("\e")

      assert_equal Riffer::Rig::Terminal::Key.new(:escape), @pty.key
    end

    it 'delivers a multi-line paste as one key instead of submitting its lines' do
      @pty.type("\e[200~one\ntwo\r\e[201~")

      assert_equal Riffer::Rig::Terminal::Key.new(:paste, "one\ntwo\r"), @pty.key
    end

    it 'holds a paste open across an idle gap longer than the read timeout' do
      @pty.type("\e[200~one\n")
      sleep Riffer::Rig::Terminal::KeyPipeline::IDLE_SECONDS * 3
      @pty.type("two\e[201~")

      assert_equal Riffer::Rig::Terminal::Key.new(:paste, "one\ntwo"), @pty.key
    end

    it 'delivers every byte of a large paste' do
      pasted = "línea\n" * 20_000
      @pty.type("\e[200~#{pasted}\e[201~")

      assert_equal pasted, @pty.key.text
    end

    it 'delivers rapid pastes whole and in order' do
      pastes = Array.new(200) { |index| "paste #{index}\n" * 50 }
      @pty.type(pastes.map { |pasted| "\e[200~#{pasted}\e[201~" }.join)

      assert_equal(pastes, pastes.map { @pty.key.text })
    end
  end
end
