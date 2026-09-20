# frozen_string_literal: true

# Declines every capability; the default host for a Runtime. Hosts are
# duck-typed, and callers check #capabilities before asking, so a declined
# capability is never asked.
class Riffer::Rig::Host
  # Returns the methods the host truly supports: none.
  #
  # @rbs return: Set[Symbol]
  def capabilities
    Set.new.freeze
  end

  # Declines the question.
  #
  # @rbs _question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(_question = nil, options: nil, secret: false)
    nil
  end

  # Declines the confirmation.
  #
  # @rbs _question: String?
  # @rbs return: bool
  def confirm(_question = nil)
    false
  end

  # Discards the message.
  #
  # @rbs _message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def notify(_message = nil, level: :info)
    nil
  end

  # Runs the block without reporting progress.
  #
  # @rbs _label: String?
  # @rbs &block: ^() -> void
  # @rbs return: void
  def progress(_label = nil, &block)
    block&.call
  end
end
