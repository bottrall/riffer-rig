# frozen_string_literal: true

class Riffer::Rig::Events::SessionStart
  include Riffer::Rig::Support::Equatable

  # @dynamic id, reason
  attr_reader :id #: String
  attr_reader :reason #: Symbol

  # @rbs id: String
  # @rbs reason: Symbol
  # @rbs return: void
  def initialize(id, reason)
    @id = id
    @reason = reason
    freeze
  end

  # @rbs return: Symbol
  def type
    :session_start
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, id: id, reason: reason }
  end
end
