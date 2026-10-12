# frozen_string_literal: true

class Riffer::Rig::Events::ToolDispatched
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :tool_dispatched, :call_id, :tool, :at

  # @dynamic call_id, tool, at
  attr_reader :call_id #: String
  attr_reader :tool #: String
  attr_reader :at #: Float

  # @rbs call_id: String
  # @rbs tool: String
  # @rbs at: Float
  # @rbs return: void
  def initialize(call_id, tool, at)
    @call_id = call_id
    @tool = tool
    @at = at
    freeze
  end
end
