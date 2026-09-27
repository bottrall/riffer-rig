# frozen_string_literal: true

class Riffer::Rig::Events::BeforeRequest < Riffer::Rig::Events::Event
  # @dynamic messages
  attr_reader :messages #: Array[::Riffer::Messages::Base]

  # @rbs messages: Array[::Riffer::Messages::Base]
  # @rbs return: void
  def initialize(messages)
    super()
    @messages = messages.dup.freeze
    freeze
  end

  # @rbs return: Symbol
  def type
    :before_request
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, messages: messages }
  end
end
