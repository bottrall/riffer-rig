# frozen_string_literal: true

class Riffer::Rig::Terminal::TurnBuffer
  # @rbs @clock: ^() -> Float
  # @rbs @started_at: Float
  # @rbs @ended_at: Float?
  # @rbs @prose: String
  # @rbs @answers: Array[String]
  # @rbs @steps: Integer
  # @rbs @in_request: bool
  # @rbs @interrupted: bool
  # @rbs @settled_usage: Riffer::Providers::TokenUsage?
  # @rbs @request_usage: Riffer::Providers::TokenUsage?

  # @dynamic ghost, tool
  attr_reader :ghost #: String?
  attr_reader :tool #: String?

  # @rbs clock: ^() -> Float
  # @rbs return: void
  def initialize(clock:)
    @clock = clock
    @started_at = clock.call
    @prose = +''
    @answers = []
    @steps = 0
    @in_request = false
    @interrupted = false
  end

  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: void
  def absorb(event)
    case event
    when Riffer::StreamEvents::TextDelta
      begin_request
      @prose << event.content
    when Riffer::StreamEvents::ToolCallDone
      begin_request
    when Riffer::StreamEvents::FinishReasonDone
      begin_request
      classify(event.finish_reason)
    when Riffer::StreamEvents::TokenUsageDone
      begin_request
      # Gemini reports a running total on every chunk, so a request's usage is
      # its last reading, not the sum of them.
      @request_usage = event.token_usage
    when Riffer::Rig::Events::BeforeToolCall
      # A provider may send no FinishReasonDone, and nothing else marks the end
      # of a request.
      settle(:tool_calls)
      @tool = event.tool
    when Riffer::Rig::Events::AfterToolCall
      # A blocked tool call skips BeforeToolCall.
      settle(:tool_calls)
      @tool = nil
    when Riffer::Rig::Events::JobExit
      # A turn the Runtime continues for a job exit has no tool call between
      # its replies to end the first request.
      settle(:stop)
    when Riffer::StreamEvents::Interrupt
      @interrupted = true
      settle(:stop)
    when Riffer::Rig::Events::TurnEnd
      settle(:stop)
      @ended_at = @clock.call
    end
  end

  # @rbs return: String
  def answer
    @answers.join("\n\n")
  end

  # @rbs return: String
  def prose
    @prose.dup
  end

  # @rbs return: bool
  def interrupted?
    @interrupted
  end

  # @rbs return: bool
  def ended?
    !@ended_at.nil?
  end

  # @rbs return: Riffer::Rig::Terminal::TurnBuffer::Stats
  def stats
    Stats.new(steps: @steps, wall_time: (@ended_at || @clock.call) - @started_at, usage: usage)
  end

  private

  # @rbs return: void
  def begin_request
    @steps += 1 unless @in_request
    @in_request = true
  end

  # @rbs finish_reason: Symbol
  # @rbs return: void
  def classify(finish_reason)
    prose = @prose
    @prose = +''
    first_line = prose[/\S.*/]
    return unless first_line

    if finish_reason == :tool_calls
      @ghost = first_line.rstrip
    else
      @answers << prose
    end
  end

  # @rbs unreported_finish_reason: Symbol
  # @rbs return: void
  def settle(unreported_finish_reason)
    classify(unreported_finish_reason)
    @settled_usage = usage
    @request_usage = nil
    @in_request = false
  end

  # @rbs return: Riffer::Providers::TokenUsage?
  def usage
    settled = @settled_usage
    request = @request_usage
    settled && request ? settled + request : settled || request
  end
end
