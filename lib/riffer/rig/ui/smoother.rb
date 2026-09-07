# frozen_string_literal: true

# Reveals streamed text on a fixed 60fps cadence so bursts of API deltas feel
# like continuous typing: deltas accumulate in a backlog and each frame
# releases a proportional slice. On a non-TTY output it is transparent —
# writes pass through synchronously and no thread ever runs.
class Riffer::Rig::UI::Smoother
  TICK_SECONDS = 1.0 / 60.0

  # A quarter per frame reveals a typical burst in ~150ms while a huge one
  # still drains fast enough to never visibly lag the model.
  DRAIN_RATE = 0.25
  MIN_CHARS_PER_TICK = 2

  def initialize(io: $stdout, theme: Riffer::Rig::UI::Theme.for(io), clock: Kernel)
    @io = io
    @theme = theme
    @clock = clock
    @backlog = +''
    @mutex = Mutex.new
    @thread = nil
    @stop = false
  end

  # Spawns the tick thread. No-op on a non-TTY output.
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
    if enabled?
      @mutex.synchronize { @backlog << content }
    else
      @io.print(content)
      @io.flush
    end
    self
  end

  # The write sits inside the mutex so a concurrent tick can't reorder a drain.
  def tick
    @mutex.synchronize do
      return if @backlog.empty?

      count = [(@backlog.length * DRAIN_RATE).ceil, MIN_CHARS_PER_TICK].max
      @io.print(@backlog.slice!(0, count))
      @io.flush
    end
  end

  # Called before non-delta output so printed order matches stream order.
  def drain
    @mutex.synchronize do
      return if @backlog.empty?

      @io.print(@backlog.slice!(0, @backlog.length))
      @io.flush
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
  end

  private

  def enabled?
    @theme.enabled && @io.respond_to?(:tty?) && @io.tty?
  end
end
