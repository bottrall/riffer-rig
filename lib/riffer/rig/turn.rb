# frozen_string_literal: true

# One turn of the agent loop, returned by Runtime#ask. A frozen value object:
# `text`, `tool_calls` and `usage` come from the run's own messages; `cost` is
# nil until pricing moves behind the Runtime.
class Riffer::Rig::Turn
  # The rig's stop-reason vocabulary: the provider's finish reasons that can
  # end a turn (mapped from riffer's outcome), the loop's own `:max_steps`, the
  # rig's future `:cancelled`, and `:error` for any other outcome riffer
  # reports.
  STOP_REASONS = %i[
    stop length context_window content_filter malformed_output max_steps cancelled error
  ].freeze #: Array[Symbol]

  COMPLETED_STOP_REASON = :stop #: Symbol
  ERROR_STOP_REASON = :error #: Symbol
  DEFAULT_TEXT = '' #: String
  DEFAULT_STOP_REASON = :error #: Symbol

  class ToolCall
    # @dynamic id, name, arguments
    attr_reader :id #: String
    attr_reader :name #: String
    attr_reader :arguments #: String

    # @rbs id: String
    # @rbs name: String
    # @rbs arguments: String
    # @rbs return: void
    def initialize(id:, name:, arguments:)
      @id = id
      @name = name
      @arguments = arguments
      freeze
    end
  end

  # @rbs @text: String
  # @rbs @stop_reason: Symbol
  # @rbs @tool_calls: Array[ToolCall]
  # @rbs @usage: Riffer::Providers::TokenUsage?

  # @dynamic text, stop_reason, tool_calls, usage
  attr_reader :text #: String
  attr_reader :stop_reason #: Symbol
  attr_reader :tool_calls #: Array[ToolCall]
  attr_reader :usage #: Riffer::Providers::TokenUsage?

  # @rbs text: String
  # @rbs stop_reason: Symbol
  # @rbs tool_calls: Array[ToolCall]
  # @rbs usage: Riffer::Providers::TokenUsage?
  # @rbs return: void
  def initialize(text: DEFAULT_TEXT, stop_reason: DEFAULT_STOP_REASON, tool_calls: [], usage: nil)
    @text = text
    @stop_reason = stop_reason
    @tool_calls = tool_calls.freeze
    @usage = usage
    freeze
  end

  # @rbs return: Float?
  def cost
    usage&.cost
  end

  # @rbs response: Riffer::Agent::Response
  # @rbs return: Riffer::Rig::Turn
  def self.from_response(response)
    text = response.messages.rfind do |message|
      message.is_a?(Riffer::Messages::Assistant)
    end&.content

    tool_calls = response.messages.flat_map do |message|
      next [] unless message.is_a?(Riffer::Messages::Assistant)

      message.tool_calls.map do |call|
        ToolCall.new(id: call.call_id, name: call.name, arguments: call.arguments)
      end
    end

    reason = response.outcome.reason
    stop_reason = if reason == :completed
                    COMPLETED_STOP_REASON
                  elsif STOP_REASONS.include?(reason)
                    reason
                  else
                    ERROR_STOP_REASON
                  end

    new(text: text || DEFAULT_TEXT, stop_reason: stop_reason, tool_calls: tool_calls, usage: response.token_usage)
  end
end
