# frozen_string_literal: true

class Riffer::Rig::Events::SessionEnd
  include Riffer::Rig::Events::Value

  # @dynamic reason
  attr_reader :reason #: Symbol

  # @rbs reason: Symbol
  # @rbs return: void
  def initialize(reason)
    @reason = reason
    freeze
  end

  # @rbs return: Symbol
  def type
    :session_end
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, reason: reason }
  end
end
