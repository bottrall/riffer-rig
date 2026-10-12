# frozen_string_literal: true

class Riffer::Rig::Events::BeforeToolCall
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :before_tool_call, :tool, :args

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
end
