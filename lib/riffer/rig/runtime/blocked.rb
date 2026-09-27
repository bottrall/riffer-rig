# frozen_string_literal: true

class Riffer::Rig::Runtime::Blocked
  # @dynamic reason
  attr_reader :reason #: String

  # @rbs reason: String
  # @rbs return: void
  def initialize(reason)
    @reason = reason
    freeze
  end
end
