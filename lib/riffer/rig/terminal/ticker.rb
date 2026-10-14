# frozen_string_literal: true

class Riffer::Rig::Terminal::Ticker
  TICK_SECONDS = 0.12 #: Float

  CHARS_PER_TOKEN = 4 #: Integer

  SKILL_TICKS = 16 #: Integer

  PHRASE_TICKS = (8..40) #: Range[Integer]

  SEPARATOR = ' · ' #: String

  # @rbs @footer: Riffer::Rig::Terminal::Frame
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @buffer: Riffer::Rig::Terminal::TurnBuffer
  # @rbs @rates: Riffer::Config::Pricing::Rates?
  # @rbs @random: Random
  # @rbs @mutex: Mutex
  # @rbs @halt: Thread::Queue[true]
  # @rbs @thread: Thread?
  # @rbs @tick: Integer
  # @rbs @tools: Integer
  # @rbs @unmetered: Integer
  # @rbs @reasoning: bool
  # @rbs @phrase: String
  # @rbs @roll_at: Integer
  # @rbs @skill: String
  # @rbs @skill_until: Integer

  # @rbs footer: Riffer::Rig::Terminal::Frame
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs buffer: Riffer::Rig::Terminal::TurnBuffer
  # @rbs rates: Riffer::Config::Pricing::Rates?
  # @rbs random: Random
  # @rbs return: void
  def initialize(footer:, theme:, buffer:, rates:, random:)
    @footer = footer
    @theme = theme
    @buffer = buffer
    @rates = rates
    @random = random
    @mutex = Mutex.new
    @halt = Queue.new
    @tick = 0
    @tools = 0
    @unmetered = 0
    @reasoning = false
    @phrase = Riffer::Rig::Terminal::Animator::NEUTRAL_LABEL
    @roll_at = 0
    @skill = ''
    @skill_until = 0
  end

  # @rbs return: void
  def start
    tick
    @thread = Thread.new { tick until @halt.pop(timeout: TICK_SECONDS) }
  end

  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: void
  def absorb(event)
    # The ticker thread reads the buffer, so the buffer takes each event under
    # the lock a frame is drawn under: no frame shows half of one.
    @mutex.synchronize do
      @buffer.absorb(event)
      @reasoning = false
      case event
      when Riffer::StreamEvents::ReasoningDelta
        @reasoning = true
        @unmetered += event.content.length
      when Riffer::StreamEvents::TextDelta
        @unmetered += event.content.length
      when Riffer::StreamEvents::ToolCallDelta
        @unmetered += event.arguments_delta.length
      when Riffer::StreamEvents::ToolCallDone
        @tools += 1
      when Riffer::StreamEvents::TokenUsageDone
        @unmetered = 0
      when Riffer::StreamEvents::SkillActivation, Riffer::Rig::Events::SkillActivated
        @skill = "✦ skill: #{event.name}"
        @skill_until = @tick + SKILL_TICKS
      end
    end
  end

  # @rbs return: void
  def tick
    room = @footer.status_room
    status = @mutex.synchronize do
      roll
      line(room).tap { @tick += 1 }
    end
    @footer.status(status)
  end

  # @rbs return: void
  def stop
    @halt << true
    @thread&.join
    @footer.status('')
  end

  private

  # @rbs return: void
  def roll
    return unless @reasoning && @tick >= @roll_at

    phrases = Riffer::Rig::Terminal::Animator::REASONING_PHRASES
    @phrase = phrases.fetch(@random.rand(phrases.size))
    @roll_at = @tick + @random.rand(PHRASE_TICKS)
  end

  # @rbs room: Integer
  # @rbs return: String
  def line(room)
    stats = @buffer.stats
    usage = stats.usage
    estimate = @unmetered / CHARS_PER_TOKEN
    bars = Riffer::Rig::Terminal::Equalizer.bars(@theme, @tick)
    segments = [
      clock(stats.wall_time), steps(stats.steps), tools, tokens(usage, estimate), cost(usage, estimate), label
    ].compact
    # A figure cut short would read as a smaller one, so the line sheds whole
    # segments from its end until it fits.
    lines = segments.size.downto(1).map { |kept| "#{bars} #{@theme.dim(segments.first(kept).join(SEPARATOR))}" }
    lines.find { |fitted| Riffer::Rig::Terminal::Columns.width(fitted) <= room } || bars
  end

  # @rbs wall_time: Float
  # @rbs return: String
  def clock(wall_time)
    wall_time.to_i.divmod(60).map { |part| part.to_s.rjust(2, '0') }.join(':')
  end

  # @rbs begun: Integer
  # @rbs return: String?
  def steps(begun)
    "step #{begun}" unless begun.zero?
  end

  # @rbs return: String?
  def tools
    "#{@tools} #{@tools == 1 ? 'tool' : 'tools'}" unless @tools.zero?
  end

  # @rbs usage: Riffer::Providers::TokenUsage?
  # @rbs estimate: Integer
  # @rbs return: String
  def tokens(usage, estimate)
    output = estimate + (usage ? usage.output_tokens : 0)
    [*("↑#{count(usage.input_tokens)}" if usage), "↓#{count(output)}", 'tok'].join(' ')
  end

  # @rbs usage: Riffer::Providers::TokenUsage?
  # @rbs estimate: Integer
  # @rbs return: String?
  def cost(usage, estimate)
    costs = [usage&.cost, @rates&.cost_for(input_tokens: 0, output_tokens: estimate)].compact
    format('$%.3f', costs.sum) unless costs.empty?
  end

  # @rbs amount: Integer
  # @rbs return: String
  def count(amount)
    return amount.to_s if amount < 1_000
    return "#{amount.fdiv(1_000).floor(1)}k" if amount < 1_000_000

    "#{amount.fdiv(1_000_000).floor(1)}M"
  end

  # @rbs return: String
  def label
    return @skill if @tick < @skill_until

    @reasoning ? @phrase : Riffer::Rig::Terminal::Animator::NEUTRAL_LABEL
  end
end
