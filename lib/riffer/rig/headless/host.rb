# frozen_string_literal: true

class Riffer::Rig::Headless::Host
  CAPABILITIES = Set[:notify, :progress].freeze #: Set[Symbol]

  # @rbs @error: IO
  # @rbs @json: bool

  # @rbs error: IO
  # @rbs json: bool
  # @rbs return: void
  def initialize(error: $stderr, json: false)
    @error = error
    @json = json
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
    # In --json the Mirror queues the Notify event onto the Runtime's stream,
    # where the printer emits it as a line; printing here would duplicate it
    # on stderr.
    return if @json

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
