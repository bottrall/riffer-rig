# frozen_string_literal: true

class Riffer::Rig::Terminal::SuspendableCursor
  # @rbs @cursor: Riffer::Rig::Terminal::_Cursor
  # @rbs @process: _Process
  # @rbs @mutex: Mutex
  # @rbs @replaced: Hash[String, Signal::trap_command]

  # @rbs cursor: Riffer::Rig::Terminal::_Cursor
  # @rbs process: _Process
  # @rbs return: void
  def initialize(cursor:, process:)
    @cursor = cursor
    @process = process
    @mutex = Mutex.new
    @replaced = {}
  end

  # @rbs return: void
  def hide
    @mutex.synchronize do
      @replaced = { 'TSTP' => on('TSTP') { suspend }, 'CONT' => on('CONT') { resume } }
      @cursor.hide
    end
  end

  # @rbs return: void
  def show
    @mutex.synchronize do
      @replaced.each { |signal, handler| Signal.trap(signal, handler) }
      @replaced = {}
      @cursor.show
    end
  end

  private

  # @rbs signal: String
  # @rbs &block: () -> void
  # @rbs return: Signal::trap_command
  def on(signal, &)
    # A trap handler runs on the main thread, which may be mid-write and
    # holding the io lock the cursor's write takes, so the handler hands the
    # work to a thread.
    Signal.trap(signal) { Thread.new(&) }
  end

  # @rbs return: void
  def suspend
    @mutex.synchronize do
      @cursor.show
      # A trapped TSTP stops nothing: only under the default disposition is
      # the re-sent signal an ordinary job-control stop.
      Signal.trap('TSTP', 'DEFAULT')
      @process.kill('TSTP', @process.pid)
    end
  end

  # @rbs return: void
  def resume
    @mutex.synchronize do
      # The cursor may have been shown for good while this thread was starting.
      return if @replaced.empty?

      on('TSTP') { suspend }
      @cursor.hide
    end
  end
end
