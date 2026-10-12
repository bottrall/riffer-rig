# frozen_string_literal: true

class Riffer::Rig::Events::BeforeToolCall
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :before_tool_call, :call_id, :tool, :args, :at

  # @dynamic call_id, tool, args, at
  attr_reader :call_id #: String
  attr_reader :tool #: String
  attr_reader :args #: Hash[Symbol, untyped]
  attr_reader :at #: Float

  # @rbs call_id: String
  # @rbs tool: String
  # @rbs args: Hash[Symbol, untyped]
  # @rbs at: Float
  # @rbs return: void
  def initialize(call_id, tool, args, at)
    @call_id = call_id
    @tool = tool
    @args = args.dup.freeze
    @at = at
    freeze
  end
end
