# frozen_string_literal: true

# Animated output is gated behind an interactive, colour-enabled TTY, so piped
# or tested runs stay silent and escape-free.
class Riffer::Rig::UI::Animator
  REVEAL_FRAME_SECONDS = 0.05 #: Float

  SPINNER_FRAME_SECONDS = 0.12 #: Float

  EQ_LEVELS = '▁▂▃▄▅▆▇█'.chars.freeze #: Array[String]

  EQ_BARS = 7 #: Integer

  NEUTRAL_LABEL = 'riffing…' #: String

  REASONING_PHRASES = [
    'contemplating…', 'pondering…', 'mulling it over…', 'reasoning…',
    'connecting the dots…', 'herding thoughts…', 'consulting the muse…',
    'doing some deep listening…', 'warming up…', 'tuning up…',
    'in the woodshed…', 'vamping…', 'finding the key…', 'counting it off…',
    'jamming internally…'
  ].freeze #: Array[String]

  REASONING_TICK_RANGE = (1..5) #: Range[Integer]

  # @rbs @io: untyped
  # @rbs @theme: Riffer::Rig::UI::Theme
  # @rbs @thread: Thread?
  # @rbs @mode: Symbol
  # @rbs @phrase: String?
  # @rbs @stop: bool

  # @rbs io: untyped
  # @rbs ?theme: Riffer::Rig::UI::Theme
  # @rbs return: void
  def initialize(io: $stdout, theme: Riffer::Rig::UI::Theme.for(io))
    @io = io
    @theme = theme
    @thread = nil
    @mode = :neutral
    @phrase = nil
  end

  # When not on a TTY, prints the final frame once instead of animating.
  #
  # @rbs frames: Array[Array[String]]
  # @rbs return: void
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

  # @rbs ?mode: Symbol
  # @rbs return: void
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

  # @rbs return: void
  def stop
    thread = @thread
    return unless thread

    @stop = true
    thread.join
    @thread = nil
    @io.print("\r\e[K")
    @io.flush
  end

  # @rbs tick: Integer
  # @rbs ?label: String
  # @rbs return: String
  def equalizer(tick, label = NEUTRAL_LABEL)
    bars = Array.new(EQ_BARS) do |i|
      height = (Math.sin((tick + i) * 0.6).abs * (EQ_LEVELS.length - 1)).round
      bar = EQ_LEVELS[height]
      i.even? ? @theme.cyan(bar) : @theme.magenta(bar)
    end
    "#{bars.join} #{@theme.grey(label)}"
  end

  private

  # @rbs return: void
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
  #
  # @rbs roll_at: Float
  # @rbs return: Float
  def roll_phrase(roll_at)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    return roll_at unless @mode == :reasoning && now >= roll_at

    @phrase = REASONING_PHRASES.sample
    now + roll_rand
  end

  # Range rand returns nil for an empty range; this one is a non-empty constant.
  #
  # @rbs return: Integer
  def roll_rand
    x = rand(REASONING_TICK_RANGE)
    x || 0
  end

  # @rbs return: String
  def label
    @mode == :reasoning ? @phrase || NEUTRAL_LABEL : NEUTRAL_LABEL
  end

  # @rbs return: bool
  def enabled?
    @theme.enabled && @io.respond_to?(:tty?) && @io.tty?
  end
end
