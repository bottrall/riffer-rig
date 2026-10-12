# frozen_string_literal: true

class Riffer::Rig::Terminal::MessageQueue
  # @dynamic messages
  attr_reader :messages #: Array[Riffer::Rig::Terminal::MessageQueue::Message]

  # @rbs messages: Array[Riffer::Rig::Terminal::MessageQueue::Message]
  # @rbs return: void
  def initialize(messages: [])
    @messages = messages.freeze
    freeze
  end

  # @rbs line: String
  # @rbs return: Riffer::Rig::Terminal::MessageQueue
  def enqueue(line)
    text = line.strip
    return self if text.empty?

    self.class.new(messages: [*messages, Message.new(text: text)])
  end

  # @rbs return: [Riffer::Rig::Terminal::MessageQueue::Message?, Riffer::Rig::Terminal::MessageQueue]
  def dequeue
    [messages.first, self.class.new(messages: messages.drop(1))]
  end
end
