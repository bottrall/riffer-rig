# frozen_string_literal: true

class Riffer::Rig::Events::AfterResponse < Riffer::Rig::Events::Event
  # @dynamic message
  attr_reader :message #: ::Riffer::Messages::Assistant

  # @rbs message: ::Riffer::Messages::Assistant
  # @rbs return: void
  def initialize(message)
    super()
    @message = message
    freeze
  end

  # @rbs return: Symbol
  def type
    :after_response
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, message: message }
  end
end
