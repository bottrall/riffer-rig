# frozen_string_literal: true

class Riffer::Rig::Terminal::Ticker
  TICK_SECONDS = 0.12 #: Float

  CHARS_PER_TOKEN = 4 #: Integer

  # @rbs @footer: Riffer::Rig::Terminal::Frame
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @buffer: Riffer::Rig::Terminal::TurnBuffer
  # @rbs @rates: ::Riffer::Catalog::Rates?
  # @rbs @mutex: Mutex
  # @rbs @halt: Thread::Queue[true]
  # @rbs @thread: Thread?
  # @rbs @tick: Integer
  # @rbs @unmetered: Integer

  # @rbs footer: Riffer::Rig::Terminal::Frame
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs buffer: Riffer::Rig::Terminal::TurnBuffer
  # @rbs rates: ::Riffer::Catalog::Rates?
  # @rbs return: void
  def initialize(footer:, theme:, buffer:, rates:)
    @footer = footer
    @theme = theme
    @buffer = buffer
    @rates = rates
    @mutex = Mutex.new
    @halt = Queue.new
    @tick = 0
    @unmetered = 0
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
      case event
      when Riffer::StreamEvents::ReasoningDelta, Riffer::StreamEvents::TextDelta
        @unmetered += event.content.length
      when Riffer::StreamEvents::ToolCallDelta
        @unmetered += event.arguments_delta.length
      when Riffer::StreamEvents::TokenUsageDone
        @unmetered = 0
      end
    end
  end

  # @rbs return: void
  def tick
    room = @footer.status_room
    jobs = @footer.job_count
    reasoning = @footer.reasoning
    status = @mutex.synchronize do
      line(room, jobs, reasoning).tap { @tick += 1 }
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

  # @rbs room: Integer
  # @rbs jobs: Integer
  # @rbs reasoning: String?
  # @rbs return: String
  def line(room, jobs, reasoning)
    stats = @buffer.stats
    usage = stats.usage
    estimate = @unmetered / CHARS_PER_TOKEN
    Riffer::Rig::Terminal::StatusBar.working(
      glyph: Riffer::Rig::Terminal::Spinner.call(@tick),
      state: stats.steps.zero? ? '' : "step #{stats.steps}",
      reasoning: reasoning,
      clock: clock(stats.wall_time),
      up_tokens: usage&.input_tokens || 0,
      down_tokens: (usage&.output_tokens || 0) + estimate,
      cost: cost(usage, estimate),
      jobs: jobs,
      theme: @theme,
      room: room
    )
  end

  # @rbs wall_time: Float
  # @rbs return: String
  def clock(wall_time)
    wall_time.to_i.divmod(60).map { |part| part.to_s.rjust(2, '0') }.join(':')
  end

  # @rbs usage: Riffer::Providers::TokenUsage?
  # @rbs estimate: Integer
  # @rbs return: Float
  def cost(usage, estimate)
    [usage&.cost, @rates&.cost_for(input_tokens: 0, output_tokens: estimate)].compact.sum(0.0)
  end
end
