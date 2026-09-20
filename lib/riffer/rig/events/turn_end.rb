# frozen_string_literal: true

class Riffer::Rig::Events::TurnEnd < Riffer::Rig::Events::Event
  # @dynamic stop_reason, usage
  attr_reader :stop_reason #: Symbol
  attr_reader :usage #: ::Riffer::Providers::TokenUsage?

  # @rbs stop_reason: Symbol
  # @rbs usage: ::Riffer::Providers::TokenUsage?
  # @rbs return: void
  def initialize(stop_reason, usage)
    super()
    @stop_reason = stop_reason
    @usage = usage
    freeze
  end

  # The USD cost of the turn's usage, or nil when pricing is missing.
  #
  # @rbs return: Float?
  def cost
    usage&.cost
  end

  # @rbs return: Symbol
  def type
    :turn_end
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, stop_reason: stop_reason, usage: usage }
  end
end
