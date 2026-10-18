# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/frame_pty'
require_relative '../../../support/key_pty'

describe Riffer::Rig::Terminal::MessageQueue do
  def queue(*lines)
    lines.reduce(Riffer::Rig::Terminal::MessageQueue.new, :enqueue)
  end

  def texts(queue)
    queue.messages.map(&:text)
  end

  def drained(queue)
    message, rest = queue.dequeue
    message ? [message.text, *drained(rest)] : []
  end

  it 'starts empty' do
    assert_empty queue.messages
  end

  it 'is frozen' do
    assert_predicate queue, :frozen?
  end

  describe '#enqueue' do
    it 'ignores a blank line' do
      assert_equal %w[one], texts(queue('one', "  \n"))
    end

    it 'adds the line to the back' do
      assert_equal %w[one two], texts(queue('one', 'two'))
    end

    it 'trims the whitespace around the line' do
      assert_equal ['/model  opus'], texts(queue("  /model  opus \n"))
    end

    it 'returns a new queue instead of changing the one it was called on' do
      original = queue('one')
      original.enqueue('two')

      assert_equal %w[one], texts(original)
    end
  end

  describe '#dequeue' do
    it 'yields no message from an empty queue' do
      assert_nil queue.dequeue.first
    end

    it 'yields the oldest message' do
      assert_equal 'one', queue('one', 'two', 'three').dequeue.first.text
    end

    it 'leaves the later messages in the order they were enqueued' do
      assert_equal %w[two three], texts(queue('one', 'two', 'three').dequeue.last)
    end

    it 'drains in the order the lines were enqueued' do
      assert_equal %w[one two three], drained(queue('one', 'two', 'three'))
    end

    it 'returns a new queue instead of changing the one it was called on' do
      original = queue('one', 'two')
      original.dequeue

      assert_equal %w[one two], texts(original)
    end
  end

  describe 'typing while a turn runs' do
    def setup
      @keys = KeyPty.new
      @pty = FramePty.new(columns: 40, rows: 8)
      @frame = Riffer::Rig::Terminal::Frame.new(
        io: @pty.slave,
        theme: Riffer::Rig::Terminal::Theme.new(enabled: false)
      )
      @frame.start
      @editor = Riffer::Rig::Terminal::LineEditor.new
      @queue = Riffer::Rig::Terminal::MessageQueue.new
      @resume = Queue.new
      @turn = Thread.new do
        @frame.append('step 1')
        @resume.pop
        @frame.append('step 2')
      end
    end

    def teardown
      @turn.kill.join
      @frame.stop
      @keys.close
      @pty.close
    end

    def type(bytes)
      @keys.type(bytes)
      bytes.size.times { press(@keys.key) }
    end

    def press(key)
      if key.name == :enter
        @queue = @queue.enqueue(@editor.text)
        @editor = @editor.submit
      else
        @editor = @editor.press(key)
      end
      @frame.input(@editor)
      @frame.queued(@queue.messages.size)
    end

    it 'queues each entered line without disturbing what the turn prints' do
      type("fix the flaky test\r/reload\r")
      @resume << :finish
      @turn.join

      assert_equal ['step 1', 'step 2', '', "› #{' ' * 24}   · 2 queued", ''], @pty.screen.rows
    end

    it 'keeps the queued lines in order when the turn is stopped early' do
      type("fix the flaky test\r/reload\r")
      @turn.kill.join

      assert_equal ['fix the flaky test', '/reload'], drained(@queue)
    end
  end
end
