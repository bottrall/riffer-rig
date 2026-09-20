# frozen_string_literal: true

# Carries a command's output text.
class Riffer::Rig::Events::CommandOutput < Riffer::Rig::Events::Event
  # @dynamic command, text
  attr_reader :command #: String
  attr_reader :text #: String

  # @rbs command: String
  # @rbs text: String
  # @rbs return: void
  def initialize(command, text)
    super()
    @command = command
    @text = text
    freeze
  end

  # @rbs return: Symbol
  def type
    :command_output
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, command: command, text: text }
  end
end
