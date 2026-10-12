# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::SuspendableCursor do
  before do
    @events = Queue.new
    @replaced = { 'TSTP' => proc {}, 'CONT' => proc {} }
    @original = @replaced.to_h { |signal, handler| [signal, Signal.trap(signal, handler)] }
    @cursor = Riffer::Rig::Terminal::SuspendableCursor.new(cursor: recording_cursor, process: recording_process)
  end

  after do
    @original.each { |signal, handler| Signal.trap(signal, handler) }
  end

  describe '#hide' do
    it 'hides the cursor' do
      @cursor.hide

      assert_equal [:hide], take(1)
    end
  end

  describe '#show' do
    it 'restores the suspend handler it replaced' do
      @cursor.hide
      @cursor.show

      assert_same @replaced['TSTP'], handler('TSTP')
    end

    it 'restores the resume handler it replaced' do
      @cursor.hide
      @cursor.show

      assert_same @replaced['CONT'], handler('CONT')
    end

    it 'shows the cursor' do
      @cursor.hide
      @cursor.show

      assert_equal %i[hide show], take(2)
    end
  end

  describe 'when the process is suspended' do
    it 'shows the cursor' do
      @cursor.hide
      suspend

      assert_equal %i[hide show], take(2)
    end

    it 'leaves the stop to the default disposition' do
      @cursor.hide
      suspend
      take(3)

      assert_equal 'SYSTEM_DEFAULT', recording_process.disposition
    end

    it 'stops its own process once the cursor is shown' do
      @cursor.hide
      suspend

      assert_equal [:hide, :show, [:kill, 'TSTP', recording_process.pid]], take(3)
    end
  end

  describe 'when the process is resumed' do
    it 'ignores a resume that lands after the cursor is shown' do
      @cursor.hide
      resume = handler('CONT')
      @cursor.show
      resume.call.join

      assert_equal %i[hide show], take(@events.size)
    end

    it 'traps the next suspend' do
      @cursor.hide
      suspend
      take(3)
      Process.kill('CONT', Process.pid)
      take(1)
      suspend

      assert_equal [:show, [:kill, 'TSTP', recording_process.pid]], take(2)
    end

    it 'hides the cursor again' do
      @cursor.hide
      Process.kill('CONT', Process.pid)

      assert_equal %i[hide hide], take(2)
    end
  end

  private

  def take(count)
    Array.new(count) { @events.pop(timeout: 5) }
  end

  def handler(signal)
    Signal.trap(signal, 'IGNORE').tap { |current| Signal.trap(signal, current) }
  end

  def suspend
    # An untrapped TSTP would stop the test run itself.
    raise 'TSTP is not trapped' unless handler('TSTP').respond_to?(:call)

    Process.kill('TSTP', Process.pid)
  end

  def recording_cursor
    events = @events
    Class.new do
      define_method(:hide) { events << :hide }

      define_method(:show) { events << :show }
    end.new
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
