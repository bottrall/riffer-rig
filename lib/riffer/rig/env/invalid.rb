# frozen_string_literal: true

class Riffer::Rig::Env::Invalid
  # @dynamic message
  attr_reader :message #: String

  # @rbs message: String
  # @rbs return: void
  def initialize(message)
    @message = message
    freeze
  end
end
