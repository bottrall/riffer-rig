# frozen_string_literal: true

# Paces streamed text onto a 60fps cadence so API bursts read as continuous
# typing. On a non-TTY output it is transparent: writes pass through
# synchronously and no thread ever runs.
class Riffer::Rig::UI::Smoother
  TICK_SECONDS = 1.0 / 60.0

  # A frame removes only a sixtieth of the remaining backlog — an exponential
  # decay whose tail keeps text flowing for a second or more, so the reveal
  # never visibly stops between chunks. The carry accrues sub-character
  # releases so the effective rate can settle at the provider's throughput;
  # the floor is fractional (10 chars/s) so it can't over-drain a backlog
  # that's trickling in slower than 60 chars/s.
  BACKLOG_FRACTION_PER_TICK = Rational(1, 60)
  MIN_CHARS_PER_TICK = Rational(1, 6)

  # A sink receives paced slices of the backlog. It defaults to raw printing
  # so a bare Smoother still writes plain text synchronously.
  class PrintSink
    def initialize(io)
      @io = io
    end

    def <<(slice)
      @io.print(slice)
      @io.flush
    end

    def finish = nil
  end

  def initialize(io: $stdout, theme: Riffer::Rig::UI::Theme.for(io), clock: Kernel, sink: PrintSink.new(io))
    @io = io
    @theme = theme
    @clock = clock
    @sink = sink
    @backlog = +''
    @carry = Rational(0)
    @mutex = Mutex.new
    @thread = nil
    @stop = false
  end

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

  def <<(content)
    @mutex.synchronize { @backlog << content }
    self
  end

  # The write sits inside the mutex so a concurrent tick can't reorder a drain.
  def tick
    @mutex.synchronize do
      return if @backlog.empty?

      @carry += [@backlog.length * BACKLOG_FRACTION_PER_TICK, MIN_CHARS_PER_TICK].max
      count = @carry.floor
      return if count.zero?

      @carry -= count
      @sink << @backlog.slice!(0, count)
    end
  end

  # Called before non-delta output so printed order matches stream order. On a
  # TTY the backlog was already paced out in slices; off-TTY it delivers the
  # full backlog at once so the sink renders whole markdown blocks.
  def drain
    @mutex.synchronize do
      return if @backlog.empty?

      @sink << @backlog.slice!(0, @backlog.length)
    end
  end

  # Idempotent: the REPL's ensure path runs it even after a happy-path finish.
  def finish
    if @thread
      @stop = true
      @thread.join
      @thread = nil
    end
    drain
    @sink.finish
  end

  private

  def enabled?
    @theme.enabled && @io.respond_to?(:tty?) && @io.tty?
  end
end
