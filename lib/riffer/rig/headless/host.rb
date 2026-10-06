# frozen_string_literal: true

class Riffer::Rig::Headless::Host
  CAPABILITIES = Set[:notify, :progress].freeze #: Set[Symbol]

  # @rbs @error: IO

  # @rbs error: IO
  # @rbs return: void
  def initialize(error: $stderr)
    @error = error
  end

  # @rbs return: Set[Symbol]
  def capabilities
    CAPABILITIES
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question = nil, options: nil, secret: false)
    nil
  end

  # @rbs question: String?
  # @rbs return: bool
  def confirm(question = nil)
    false
  end

  # @rbs message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message = nil, level: :info)
    @error.puts(message.to_s)
  end

  # @rbs label: String?
  # @rbs &block: ? () -> void
  # @rbs return: void
  def progress(label = nil, &block)
    @error.puts(label) if label
    block&.call
  end
end
