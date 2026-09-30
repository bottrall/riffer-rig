# frozen_string_literal: true

class Riffer::Rig::Events::BeforeRequest
  include Riffer::Rig::Support::Equatable

  # @dynamic messages
  attr_reader :messages #: Array[::Riffer::Messages::Base]

  # @rbs messages: Array[::Riffer::Messages::Base]
  # @rbs return: void
  def initialize(messages)
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
