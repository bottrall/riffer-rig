# frozen_string_literal: true

class Riffer::Rig::Events::BeforePrompt < Riffer::Rig::Events::Event
  # @dynamic text
  attr_reader :text #: String

  # @rbs text: String
  # @rbs return: void
  def initialize(text)
    super()
    @text = text
    freeze
  end

  # @rbs return: Symbol
  def type
    :before_prompt
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, text: text }
  end
end
