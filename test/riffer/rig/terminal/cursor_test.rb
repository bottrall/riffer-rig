# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Terminal::Cursor do
  def setup
    @io = StringIO.new
    @cursor = Riffer::Rig::Terminal::Cursor.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
    @events = Queue.new
    @replaced = { 'TSTP' => proc {}, 'CONT' => proc {} }
    @original = @replaced.to_h { |signal, handler| [signal, Signal.trap(signal, handler)] }
  end

  def teardown
    @original.each { |signal, handler| Signal.trap(signal, handler) }
  end

  it 'hide is a no op when not a tty' do
    @cursor.hide

    assert_equal '', @io.string
  end

  it 'hide is a no op when the theme is disabled on a tty' do
    @cursor = Riffer::Rig::Terminal::Cursor.new(io: tty_io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))

    @cursor.hide

    assert_equal '', @io.string
  end

  it 'hide is a no op when the theme is enabled but the io is not a tty' do
    @io = StringIO.new
    @cursor = Riffer::Rig::Terminal::Cursor.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))

    @cursor.hide

    assert_equal '', @io.string
  end

  it 'hide traps nothing when disabled' do
    @cursor.hide

    assert_equal @replaced, handlers
  end

  it 'show is a no op when not a tty' do
    @cursor.show

    assert_equal '', @io.string
  end

  it 'show restores the handlers hide replaced' do
    @cursor = enabled_cursor

    @cursor.hide
    @cursor.show

    assert_equal @replaced, handlers
  end

  it 'show then hide print their sequences when enabled' do
    @cursor = enabled_cursor

    @cursor.show
    @cursor.hide

    assert_equal "\e[?25h\e[?25l", @io.string
  end

  describe 'when the process is suspended' do
    it 'shows the cursor' do
      hidden_cursor

      assert_equal "\e[?25h", suspend.first
    end

    it 'leaves the stop to the default disposition' do
      hidden_cursor
      suspend

      assert_equal 'SYSTEM_DEFAULT', recording_process.disposition
    end

    it 'stops its own process once the cursor is shown' do
      hidden_cursor

      assert_equal [:kill, 'TSTP', recording_process.pid], suspend.last
    end
  end

  describe 'when the process is resumed' do
    it 'ignores a resume that lands after the cursor is shown' do
      cursor = hidden_cursor
      late = handlers['CONT']
      cursor.show
      late.call.join

      assert_equal "\e[?25l\e[?25h", @io.string
    end

    it 'traps the next suspend' do
      hidden_cursor
      suspend
      resume

      assert_equal ["\e[?25h", [:kill, 'TSTP', recording_process.pid]], suspend
    end

    it 'hides the cursor again' do
      hidden_cursor

      assert_equal ["\e[?25l"], resume
    end
  end

  private

  def tty_io
    events = @events
    @io = StringIO.new
    @io.define_singleton_method(:tty?) { true }
    @io.define_singleton_method(:print) do |sequence|
      super(sequence)
      events << sequence
    end
    @io
  end

  def enabled_cursor
    Riffer::Rig::Terminal::Cursor.new(
      io: tty_io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: true),
      process: recording_process
    )
  end

  def hidden_cursor
    enabled_cursor.tap do |cursor|
      cursor.hide
      take(1)
    end
  end

  def handlers
    @replaced.keys.to_h do |signal|
      [signal, Signal.trap(signal, 'IGNORE').tap { |handler| Signal.trap(signal, handler) }]
    end
  end

  def suspend
    # An untrapped TSTP would stop the test run itself.
    raise 'TSTP is not trapped' unless handlers['TSTP'].respond_to?(:call)

    Process.kill('TSTP', Process.pid)
    # Taking the last thing the handler's thread does keeps it from trapping
    # into the next test.
    take(2)
  end

  def resume
    Process.kill('CONT', Process.pid)
    take(1)
  end

  def take(count)
    Array.new(count) { @events.pop(timeout: 5) }
  end

  def recording_process
    events = @events
    @recording_process ||= Class.new do
      attr_reader :disposition

      def pid = 4242

      define_method(:kill) do |signal, pid|
        @disposition = Signal.trap(signal, 'DEFAULT')
        events << [:kill, signal, pid]
      end
    end.new
  end
end
