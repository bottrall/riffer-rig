# frozen_string_literal: true

class Riffer::Rig::Terminal::TickerDisplay
  STOPPING = 'stopping…' #: String

  # @rbs @frame: Riffer::Rig::Terminal::Frame
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @peek: Riffer::Rig::Terminal::Peek
  # @rbs @catalog: ::Riffer::Catalog
  # @rbs @random: Random
  # @rbs @clock: ^() -> Float
  # @rbs @mutex: Mutex
  # @rbs @buffer: Riffer::Rig::Terminal::TurnBuffer?
  # @rbs @ticker: Riffer::Rig::Terminal::Ticker?

  # @rbs frame: Riffer::Rig::Terminal::Frame
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs peek: Riffer::Rig::Terminal::Peek
  # @rbs catalog: ::Riffer::Catalog
  # @rbs random: Random
  # @rbs clock: ^() -> Float
  # @rbs return: void
  def initialize(frame:, theme:, peek:, catalog:, random:, clock:)
    @frame = frame
    @theme = theme
    @peek = peek
    @catalog = catalog
    @random = random
    @clock = clock
    @mutex = Mutex.new
    @buffer = nil
    @ticker = nil
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def start(runtime)
    buffer = Riffer::Rig::Terminal::TurnBuffer.new(clock: @clock)
    ticker = Riffer::Rig::Terminal::Ticker.new(
      footer: @frame,
      theme: @theme,
      buffer: buffer,
      rates: @catalog.rates_for(runtime.model),
      random: @random
    )
    @mutex.synchronize do
      @buffer = buffer
      @ticker = ticker
      @peek.watch(buffer)
      ticker.start
    end
  end

  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: void
  def absorb(event)
    @ticker&.absorb(event)
    @peek.refresh
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def cancel(runtime)
    @mutex.synchronize do
      ticker = @ticker
      # Ctrl-C is handed over on its own thread, which can arrive once the
      # turn it was for has ended: a status drawn then would outlive that turn.
      return unless ticker

      # The ticker redraws the status line on every tick.
      ticker.stop
      @frame.status(@theme.dim(STOPPING))
      runtime.cancel
    end
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def finish(runtime)
    @mutex.synchronize do
      @ticker&.stop
      @ticker = nil
    end
    @peek.unwatch
    buffer = @buffer
    return unless buffer&.ended?

    report = Riffer::Rig::Terminal::TurnReport.call(buffer, runtime.tally, theme: @theme, width: @frame.measure&.last)
    @frame.append(report)
  end
end
