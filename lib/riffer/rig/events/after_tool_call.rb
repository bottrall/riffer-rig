# frozen_string_literal: true

class Riffer::Rig::Events::AfterToolCall
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :after_tool_call, :tool, :args, :result

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
end
