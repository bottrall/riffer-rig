# frozen_string_literal: true

class Riffer::Rig::Events::ToolDispatched
  include Riffer::Rig::Support::Equatable

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

  # @rbs return: Symbol
  def type
    :tool_dispatched
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, call_id: call_id, tool: tool, at: at }
  end
end
