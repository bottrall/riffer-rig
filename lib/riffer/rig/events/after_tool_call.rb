# frozen_string_literal: true

class Riffer::Rig::Events::AfterToolCall
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :after_tool_call, :call_id, :tool, :args, :result, :at, :duration

  # @dynamic call_id, tool, args, result, at, duration
  attr_reader :call_id #: String
  attr_reader :tool #: String
  attr_reader :args #: Hash[Symbol, untyped]
  attr_reader :result #: ::Riffer::Tools::Response
  attr_reader :at #: Float
  attr_reader :duration #: Float

  # @rbs call_id: String
  # @rbs tool: String
  # @rbs args: Hash[Symbol, untyped]
  # @rbs result: ::Riffer::Tools::Response
  # @rbs at: Float
  # @rbs duration: Float
  # @rbs return: void
  def initialize(call_id, tool, args, result, at, duration)
    @call_id = call_id
    @tool = tool
    @args = args.dup.freeze
    @result = result
    @at = at
    @duration = duration
    freeze
  end
end
