# frozen_string_literal: true

class Riffer::Rig::Terminal::Cursor
  HIDE = "\e[?25l" #: String

  SHOW = "\e[?25h" #: String

  # @rbs @io: IO
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @process: _Process
  # @rbs @mutex: Mutex
  # @rbs @replaced: Hash[String, Signal::trap_command]

  # @rbs io: IO
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs process: _Process
  # @rbs return: void
  def initialize(io: $stdout, theme: Riffer::Rig::Terminal::Theme.for(io), process: Process)
    @io = io
    @theme = theme
    @process = process
    @mutex = Mutex.new
    @replaced = {}
  end

  # @rbs return: void
  def hide
    return unless enabled?

    @mutex.synchronize do
      @replaced = { 'TSTP' => on('TSTP') { suspend }, 'CONT' => on('CONT') { resume } }
      write(HIDE)
    end
  end

  # @rbs return: void
  def show
    return unless enabled?

    @mutex.synchronize do
      @replaced.each { |signal, handler| Signal.trap(signal, handler) }
      @replaced = {}
      write(SHOW)
    end
  end

  private

  # @rbs sequence: String
  # @rbs return: void
  def write(sequence)
    @io.print(sequence)
    @io.flush
  end

  # @rbs return: bool
  def enabled?
    @theme.enabled && @io.tty?
  end

  # @rbs signal: String
  # @rbs &block: () -> void
  # @rbs return: Signal::trap_command
  def on(signal, &)
    # A trap handler runs on the main thread, which may be mid-write and
    # holding the io lock a write takes, so the handler hands the work to a
    # thread.
    Signal.trap(signal) { Thread.new(&) }
  end

  # @rbs return: void
  def suspend
    @mutex.synchronize do
      write(SHOW)
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
      write(HIDE)
    end
  end
end
