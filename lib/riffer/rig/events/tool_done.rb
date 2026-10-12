# frozen_string_literal: true

class Riffer::Rig::Events::ToolDone
  include Riffer::Rig::Support::Equatable

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

  # @rbs return: Symbol
  def type
    :tool_done
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, call_id: call_id, tool: tool, at: at, duration: duration, error: error }
  end
end
