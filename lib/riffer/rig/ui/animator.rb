# frozen_string_literal: true

# Animated output is gated behind an interactive, colour-enabled TTY, so piped
# or tested runs stay silent and escape-free.
class Riffer::Rig::UI::Animator
  REVEAL_FRAME_SECONDS = 0.05
  SPINNER_FRAME_SECONDS = 0.12
  EQ_LEVELS = '▁▂▃▄▅▆▇█'.chars.freeze
  EQ_BARS = 7
  NEUTRAL_LABEL = 'riffing…'
  REASONING_PHRASES = [
    'contemplating…', 'pondering…', 'mulling it over…', 'reasoning…',
    'connecting the dots…', 'herding thoughts…', 'consulting the muse…',
    'doing some deep listening…', 'warming up…', 'tuning up…',
    'in the woodshed…', 'vamping…', 'finding the key…', 'counting it off…',
    'jamming internally…'
  ].freeze
  REASONING_TICK_RANGE = (1..5)

  def initialize(io: $stdout, theme: Riffer::Rig::UI::Theme.for(io))
    @io = io
    @theme = theme
    @thread = nil
    @mode = :neutral
    @phrase = nil
  end

  # When not on a TTY, prints the final frame once instead of animating.
  def reveal(frames)
    unless enabled?
      frames.last.each { |line| @io.puts(line) }
      return
    end

    height = frames.first.length
    frames.each_with_index do |lines, index|
      lines.each { |line| @io.print("#{line}\e[K\n") }
      @io.flush
      sleep(REVEAL_FRAME_SECONDS)
      @io.print("\e[#{height}A\r") unless index == frames.length - 1
    end
  end

  def start(mode = :neutral)
    return unless enabled?

    if @thread
      @mode = mode
      return
    end

    @mode = mode
    @stop = false
    @thread = Thread.new { animate }
  end

  def stop
    return unless @thread

    @stop = true
    @thread.join
    @thread = nil
    @io.print("\r\e[K")
    @io.flush
  end

  def equalizer(tick, label = NEUTRAL_LABEL)
    bars = Array.new(EQ_BARS) do |i|
      height = (Math.sin((tick + i) * 0.6).abs * (EQ_LEVELS.length - 1)).round
      bar = EQ_LEVELS[height]
      i.even? ? @theme.cyan(bar) : @theme.magenta(bar)
    end
    "#{bars.join} #{@theme.grey(label)}"
  end

  private

  def animate
    tick = 0
    roll_at = 0.0 # force an immediate phrase roll when entering reasoning mode
    until @stop
      roll_at = roll_phrase(roll_at)
      @io.print("\r  #{equalizer(tick, label)}\e[K")
      @io.flush
      sleep(SPINNER_FRAME_SECONDS)
      tick += 1
    end
  end

  # Re-rolls both phrase and duration whenever the reasoning tick expires.
  def roll_phrase(roll_at)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return roll_at unless @mode == :reasoning && now >= roll_at

    @phrase = REASONING_PHRASES.sample
    now + rand(REASONING_TICK_RANGE)
  end

  def label
    @mode == :reasoning ? @phrase : NEUTRAL_LABEL
  end

  def enabled?
    @theme.enabled && @io.respond_to?(:tty?) && @io.tty?
  end
end
