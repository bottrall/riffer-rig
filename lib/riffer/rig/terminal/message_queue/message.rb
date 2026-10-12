# frozen_string_literal: true

class Riffer::Rig::Terminal::MessageQueue::Message
  # @dynamic text
  attr_reader :text #: String

  # @rbs text: String
  # @rbs return: void
  def initialize(text:)
    @text = text
    freeze
  end
end
