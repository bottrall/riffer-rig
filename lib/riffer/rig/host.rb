# frozen_string_literal: true

class Riffer::Rig::Host
  # @rbs return: Set[Symbol]
  def capabilities
    Set.new.freeze
  end

  # @rbs _question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(_question = nil, options: nil, secret: false)
    nil
  end

  # @rbs _question: String?
  # @rbs return: bool
  def confirm(_question = nil)
    false
  end

  # @rbs _message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def notify(_message = nil, level: :info)
    nil
  end

  # @rbs _label: String?
  # @rbs &block: ^() -> void
  # @rbs return: void
  def progress(_label = nil, &block)
    block&.call
  end
end
