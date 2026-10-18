# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/frame_pty'
require_relative '../../../support/key_pty'

class RecordingFrame
  attr_reader :peeks

  def initialize
    @peeks = []
  end

  def peek(content)
    @peeks << content
  end
end

describe Riffer::Rig::Terminal::Peek do
  def frame
    @frame ||= RecordingFrame.new
  end

  def peek
    @peek ||= Riffer::Rig::Terminal::Peek.new(frame: frame)
  end

  def watching(*events)
    Riffer::Rig::Terminal::TurnBuffer.new(clock: -> { 0.0 }).tap do |buffer|
      events.each { |event| buffer.absorb(event) }
      peek.watch(buffer)
    end
  end

  def ctrl_t
    Riffer::Rig::Terminal::Key.new(:ctrl_t)
  end

  def text(content)
    Riffer::StreamEvents::TextDelta.new(content)
  end

  def tool_calls
    Riffer::StreamEvents::FinishReasonDone.new(finish_reason: :tool_calls)
  end

  def before_tool
    Riffer::Rig::Events::BeforeToolCall.new('call_1', 'read', {}, 0.0)
  end

  def after_tool
    Riffer::Rig::Events::AfterToolCall.new('call_1', 'read', {}, Riffer::Tools::Response.text('ok'), 0.0, 0.0)
  end

  describe '#watch' do
    it 'opens nothing by itself' do
      watching(text('Let me look.'))

      assert_empty frame.peeks
    end

    it 'shows the turn that replaced the one it was watching' do
      watching(text('Let me look.'))
      watching(text('Now the tests.'))

      peek.press(ctrl_t)

      assert_equal ['Now the tests.'], frame.peeks
    end
  end

  describe '#press' do
    it 'ignores every key but Ctrl-T' do
      watching(text('Let me look.'))

      peek.press(Riffer::Rig::Terminal::Key.new(:text, 't'))

      assert_empty frame.peeks
    end

    it 'does nothing when no turn is running' do
      peek.press(ctrl_t)

      assert_empty frame.peeks
    end

    it 'shows what the turn has buffered' do
      watching(text('Let me look.'))

      peek.press(ctrl_t)

      assert_equal ['Let me look.'], frame.peeks
    end

    it 'hides it again on the next press' do
      watching(text('Let me look.'))

      2.times { peek.press(ctrl_t) }

      assert_equal ['Let me look.', ''], frame.peeks
    end
  end

  describe '#refresh' do
    it 'draws nothing while the peek is closed' do
      watching(text('Let me look.'))

      peek.refresh

      assert_empty frame.peeks
    end

    it 'redraws the open peek with what the turn has buffered since' do
      turn = watching(text('Let me'))
      peek.press(ctrl_t)
      turn.absorb(text(' look.'))

      peek.refresh

      assert_equal ['Let me', 'Let me look.'], frame.peeks
    end

    it 'draws a peek read before it was toggled off ahead of hiding it' do
      watching(text('Let me look.'))
      peek.press(ctrl_t)
      parking = [true]
      frame.define_singleton_method(:peek) do |content|
        Thread.stop if parking.shift
        super(content)
      end

      refreshing = Thread.new { peek.refresh }
      Thread.pass until refreshing.stop?
      toggling = Thread.new { peek.press(ctrl_t) }
      Thread.pass until toggling.stop?
      refreshing.run
      [refreshing, toggling].each(&:join)

      assert_equal ['Let me look.', 'Let me look.', ''], frame.peeks
    end
  end

  describe '#unwatch' do
    it 'leaves Ctrl-T with no turn to show' do
      watching(text('Let me look.'))
      peek.unwatch

      peek.press(ctrl_t)

      assert_equal [''], frame.peeks
    end

    it 'starts the next turn with the peek closed' do
      watching(text('Let me look.'))
      peek.press(ctrl_t)
      peek.unwatch
      watching(text('Now the tests.'))

      peek.refresh

      assert_equal ['Let me look.', ''], frame.peeks
    end

    it 'hides the open peek' do
      watching(text('Let me look.'))
      peek.press(ctrl_t)

      peek.unwatch

      assert_equal ['Let me look.', ''], frame.peeks
    end
  end

  describe '#content' do
    def shown(*events)
      watching(*events)
      peek.press(ctrl_t)
      frame.peeks.last
    end

    it 'is empty before the turn buffers anything' do
      assert_empty shown
    end

    it 'trims the blank lines around the prose' do
      assert_equal "Let me look.\n\nThen compare.", shown(text("\n\nLet me look.\n\nThen compare.\n\n"))
    end

    it 'falls back to the ghost once the request that wrote it has ended' do
      assert_equal 'Let me look.', shown(text("Let me look.\n\nThen compare."), tool_calls)
    end

    it 'shows the prose of the next request in place of the ghost' do
      assert_equal 'Now the tests.', shown(text('Let me look.'), tool_calls, text('Now the tests.'))
    end

    it 'names the tool in flight under the ghost' do
      assert_equal "Let me look.\n⚙ read", shown(text('Let me look.'), before_tool)
    end

    it 'names the tool in flight alone when no prose led to it' do
      assert_equal '⚙ read', shown(before_tool)
    end

    it 'removes the control characters that could drive the terminal' do
      assert_equal 'Let [2Jme look.', shown(text("Let \e[2Jme\a look.\r"))
    end

    it 'widens a tab to the columns it is drawn in' do
      assert_equal "if done\n    return", shown(text("if done\n\treturn"))
    end
  end

  describe 'a turn peeked at from the keyboard' do
    before do
      @keys = KeyPty.new
      @pty = FramePty.new(columns: 40, rows: 5)
      @footer = Riffer::Rig::Terminal::Frame.new(
        io: @pty.slave,
        theme: Riffer::Rig::Terminal::Theme.new(enabled: false)
      )
      @footer.start
      @footer.append("earlier answer\n› fix the flaky test")
      @footer.status('working')
      @turn = Riffer::Rig::Terminal::TurnBuffer.new(clock: -> { 0.0 })
      @peeked = Riffer::Rig::Terminal::Peek.new(frame: @footer)
      @peeked.watch(@turn)
      stream(text('Let me look at the session test.'))
    end

    after do
      @footer.stop
      @keys.close
      @pty.close
    end

    def stream(*events)
      events.each do |event|
        @turn.absorb(event)
        @peeked.refresh
      end
    end

    def type(bytes)
      @keys.type(bytes)
      bytes.size.times { @peeked.press(@keys.key) }
    end

    def page
      @pty.screen.scrollback + @pty.screen.rows
    end

    it 'draws the buffered prose above the footer on Ctrl-T' do
      type("\x14")

      assert_equal(
        ['› fix the flaky test', '', '  Let me look at the session test.', '  working', '›'],
        @pty.screen.rows
      )
    end

    it 'follows the turn while the peek is open' do
      type("\x14")

      stream(tool_calls, before_tool)

      assert_equal ['', '  Let me look at the session test.', '  ⚙ read', '  working', '›'], @pty.screen.rows
    end

    it 'erases the peek on the next Ctrl-T' do
      type("\x14\x14")

      assert_equal ['earlier answer', '› fix the flaky test', '', '  working', '›'], page
    end

    it 'leaves the scrollback clean after a peek toggled on and off' do
      type("\x14")
      stream(tool_calls, before_tool)
      type("\x14")
      stream(after_tool, text('All done.'))
      @peeked.unwatch

      @footer.append('All done.')

      assert_equal ['earlier answer', '› fix the flaky test', 'All done.', '', '  working', '›'], page
    end

    it 'leaves the scrollback clean when the turn ends with the peek open' do
      type("\x14")
      stream(tool_calls, before_tool, after_tool, text('All done.'))
      @peeked.unwatch

      @footer.append('All done.')

      assert_equal ['earlier answer', '› fix the flaky test', 'All done.', '', '  working', '›'], page
    end

    it 'does nothing on Ctrl-T once the turn has ended' do
      @peeked.unwatch

      type("\x14")

      assert_equal ['earlier answer', '› fix the flaky test', '', '  working', '›'], page
    end
  end
end
