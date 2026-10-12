# frozen_string_literal: true

class Riffer::Rig::Events::ToolDone
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :tool_done, :call_id, :tool, :at, :duration, :error

  # @dynamic call_id, tool, at, duration, error
  attr_reader :call_id #: String
  attr_reader :tool #: String
  attr_reader :at #: Float
  attr_reader :duration #: Float
  attr_reader :error #: bool

  # @rbs call_id: String
  # @rbs tool: String
  # @rbs at: Float
  # @rbs duration: Float
  # @rbs error: bool
  # @rbs return: void
  def initialize(call_id, tool, at, duration, error)
    @call_id = call_id
    @tool = tool
    @at = at
    @duration = duration
    @error = error
    freeze
  end
end
