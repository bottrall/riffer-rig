# frozen_string_literal: true

# Reveals streamed text on a fixed 60fps cadence so bursts of API deltas feel
# like continuous typing. Deltas accumulate in a backlog; each frame releases
# a proportional slice, so small bursts glide out over a few frames while big
# ones catch up quickly. On a non-TTY output the smoother is transparent:
# writes pass through synchronously and no thread ever runs.
class Riffer::Rig::UI::Smoother
  TICK_SECONDS = 1.0 / 60.0

  # Each frame releases a quarter of the backlog (at least MIN_CHARS_PER_TICK),
  # so a typical burst is ~90% revealed in about 150ms while a huge one drains
  # fast enough to never visibly lag the model.
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

  # Queues a delta for paced release, or prints it straight through when
  # disabled. Returns self so deltas can be chained.
  def <<(content)
    if enabled?
      @mutex.synchronize { @backlog << content }
    else
      @io.print(content)
      @io.flush
    end
    self
  end

  # Releases one frame's worth of backlog: a quarter of it, at least
  # MIN_CHARS_PER_TICK characters, never more than remains. The write happens
  # under the mutex so concurrent tick/drain calls can't reorder output.
  def tick
    @mutex.synchronize do
      return if @backlog.empty?

      count = [(@backlog.length * DRAIN_RATE).ceil, MIN_CHARS_PER_TICK].max
      @io.print(@backlog.slice!(0, count))
      @io.flush
    end
  end

  # Flushes the whole backlog immediately, synchronously. Called before any
  # non-delta output so printed order always matches stream order.
  def drain
    @mutex.synchronize do
      return if @backlog.empty?

      @io.print(@backlog.slice!(0, @backlog.length))
      @io.flush
    end
  end

  # Stops the tick thread and flushes whatever remains. Safe to call when
  # never started, and repeatedly.
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
