# frozen_string_literal: true

# Paces streamed text onto a 60fps cadence so API bursts read as continuous
# typing. On a non-TTY output it is transparent: writes pass through
# synchronously and no thread ever runs.
class Riffer::Rig::UI::Smoother
  TICK_SECONDS = 1.0 / 60.0 #: Float

  # A frame removes only a sixtieth of the remaining backlog — an exponential
  # decay whose tail keeps text flowing for a second or more, so the reveal
  # never visibly stops between chunks. The carry accrues sub-character
  # releases so the effective rate can settle at the provider's throughput;
  # the floor is fractional (10 chars/s) so it can't over-drain a backlog
  # that's trickling in slower than 60 chars/s.
  #
  BACKLOG_FRACTION_PER_TICK = Rational(1, 60) #: Rational

  MIN_CHARS_PER_TICK = Rational(1, 6) #: Rational

  # @rbs @io: untyped
  # @rbs @theme: Riffer::Rig::UI::Theme
  # @rbs @clock: singleton(Kernel)
  # @rbs @backlog: String
  # @rbs @carry: Rational
  # @rbs @mutex: Mutex
  # @rbs @thread: Thread?
  # @rbs @stop: bool
  # @rbs @newline_pending: bool

  # @rbs io: untyped
  # @rbs ?theme: Riffer::Rig::UI::Theme
  # @rbs clock: singleton(Kernel)
  # @rbs return: void
  def initialize(io: $stdout, theme: Riffer::Rig::UI::Theme.for(io), clock: Kernel)
    @io = io
    @theme = theme
    @clock = clock
    @backlog = +''
    @carry = Rational(0)
    @mutex = Mutex.new
    @thread = nil
    @stop = false
    @newline_pending = false
  end

  # @rbs return: void
  def start
    return unless enabled?
    return if @thread

    @stop = false
    @thread = Thread.new do
      until @stop
        tick
        @clock.sleep(TICK_SECONDS)
      end
    end
  end

  # @rbs content: String
  # @rbs return: self
  def <<(content)
    @mutex.synchronize do
      if enabled?
        @backlog << content
      else
        @io.print(content)
        @io.flush
      end
      @newline_pending = !content.end_with?("\n")
    end
    self
  end

  # The write sits inside the mutex so a concurrent tick can't reorder a drain.
  #
  # @rbs return: void
  def tick
    @mutex.synchronize do
      return if @backlog.empty?

      @carry += [@backlog.length * BACKLOG_FRACTION_PER_TICK, MIN_CHARS_PER_TICK].max
      count = @carry.floor
      return if count.zero?

      @carry -= count
      chunk = @backlog.slice!(0, count) || ''
      @newline_pending = !chunk.end_with?("\n")
      @io.print(chunk)
      @io.flush
    end
  end

  # Called before non-prose output so printed order matches stream order. The
  # backlog is flushed, then any partial prose block the model left without a
  # trailing newline gets one, so block spacing never depends on the model's
  # last character.
  #
  # @rbs return: void
  def drain
    @mutex.synchronize do
      unless @backlog.empty?
        backlog = @backlog.slice!(0, @backlog.length) || ''
        @newline_pending = !backlog.end_with?("\n")
        @io.print(backlog)
      end
      return unless @newline_pending

      @newline_pending = false
      @io.print("\n")
      @io.flush
    end
  end

  # Idempotent: the REPL's ensure path runs it even after a happy-path finish.
  #
  # @rbs return: void
  def finish
    thread = @thread
    if thread
      @stop = true
      thread.join
      @thread = nil
    end
    drain
  end

  private

  # @rbs return: bool
  def enabled?
    @theme.enabled && @io.respond_to?(:tty?) && @io.tty?
  end
end
