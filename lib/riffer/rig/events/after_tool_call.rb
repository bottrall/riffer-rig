# frozen_string_literal: true

class Riffer::Rig::Events::AfterToolCall
  include Riffer::Rig::Support::Equatable

  # @dynamic tool, args, result
  attr_reader :tool #: String
  attr_reader :args #: Hash[Symbol, untyped]
  attr_reader :result #: ::Riffer::Tools::Response

  # @rbs tool: String
  # @rbs args: Hash[Symbol, untyped]
  # @rbs result: ::Riffer::Tools::Response
  # @rbs return: void
  def initialize(tool, args, result)
    @tool = tool
    @args = args.dup.freeze
    @result = result
    freeze
  end

  # @rbs return: Symbol
  def type
    :after_tool_call
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, tool: tool, args: args, result: result }
  end
end
