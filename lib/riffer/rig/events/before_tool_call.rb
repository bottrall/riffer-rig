# frozen_string_literal: true

class Riffer::Rig::Events::BeforeToolCall
  include Riffer::Rig::Events::Value

  # @dynamic tool, args
  attr_reader :tool #: String
  attr_reader :args #: Hash[Symbol, untyped]

  # @rbs tool: String
  # @rbs args: Hash[Symbol, untyped]
  # @rbs return: void
  def initialize(tool, args)
    @tool = tool
    @args = args.dup.freeze
    freeze
  end

  # @rbs return: Symbol
  def type
    :before_tool_call
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, tool: tool, args: args }
  end
end
