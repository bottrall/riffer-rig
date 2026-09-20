# frozen_string_literal: true

# Ends every prompt's stream with the run's stop reason and token usage.
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

  # Returns the USD cost of the turn's usage, or nil when the model is unpriced.
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
