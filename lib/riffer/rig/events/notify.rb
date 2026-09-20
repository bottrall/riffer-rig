# frozen_string_literal: true

class Riffer::Rig::Events::Notify < Riffer::Rig::Events::Event
  # @dynamic message, level
  attr_reader :message #: String?
  attr_reader :level #: Symbol

  # @rbs message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def initialize(message, level)
    super()
    @message = message
    @level = level
    freeze
  end

  # @rbs return: Symbol
  def type
    :notify
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, message: message, level: level }
  end
end
