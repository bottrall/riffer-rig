# frozen_string_literal: true

# Closes a session's stream.
class Riffer::Rig::Events::SessionEnd < Riffer::Rig::Events::Event
  # @dynamic reason
  attr_reader :reason #: Symbol

  # @rbs reason: Symbol
  # @rbs return: void
  def initialize(reason)
    super()
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
