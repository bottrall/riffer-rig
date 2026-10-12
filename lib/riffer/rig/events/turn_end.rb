# frozen_string_literal: true

class Riffer::Rig::Events::TurnEnd
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :turn_end, :stop_reason, :usage

  # @dynamic stop_reason, usage
  attr_reader :stop_reason #: Symbol
  attr_reader :usage #: ::Riffer::Providers::TokenUsage?

  # @rbs stop_reason: Symbol
  # @rbs usage: ::Riffer::Providers::TokenUsage?
  # @rbs return: void
  def initialize(stop_reason, usage)
    @stop_reason = stop_reason
    @usage = usage
    freeze
  end

  # @rbs return: Float?
  def cost
    usage&.cost
  end
end
