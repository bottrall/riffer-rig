# frozen_string_literal: true

class Riffer::Rig::Terminal::QuietDisplay
  # @rbs @io: IO
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @clock: ^() -> Float
  # @rbs @buffer: Riffer::Rig::Terminal::TurnBuffer?

  # @rbs io: IO
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs clock: ^() -> Float
  # @rbs return: void
  def initialize(io:, theme:, clock:)
    @io = io
    @theme = theme
    @clock = clock
    @buffer = nil
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def start(runtime) # rubocop:disable Lint/UnusedMethodArgument -- the display contract's parameter, which rbs-inline leaves untyped once it is `_`-prefixed
    @buffer = Riffer::Rig::Terminal::TurnBuffer.new(clock: @clock)
  end

  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: void
  def absorb(event)
    @buffer&.absorb(event)
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def cancel(runtime)
    runtime.cancel
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def finish(runtime)
    buffer = @buffer
    return unless buffer&.ended?

    width = Riffer::Rig::Terminal::Frame.measure(@io)&.last
    @io.print(Riffer::Rig::Terminal::TurnReport.call(buffer, runtime.tally, theme: @theme, width: width))
    @io.flush
  end
end
