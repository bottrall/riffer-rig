# frozen_string_literal: true

# Wraps the given host and mirrors every notify into a rig-level
# Riffer::Rig::Events::Notify on the next prompt's stream, so stream consumers see
# extension errors too.
# @rbs!
#   interface _Host
#     def ask: (?String?, ?options: Array[String]?, ?secret: bool) -> String?
#     def confirm: (?String?) -> bool
#     def notify: (?String?, ?level: Symbol) -> void
#     def progress: (?String?) { () -> void } -> void
#     def capabilities: () -> Set[Symbol]
#   end

class Riffer::Rig::NotifyingHost
  # @rbs @host: _Host
  # @rbs @queue: Array[(Riffer::Rig::Events::Notify | Riffer::Rig::Events::SessionEnd)]

  # @dynamic capabilities
  attr_reader :capabilities #: Set[Symbol]

  # @rbs host: _Host
  # @rbs return: void
  def initialize(host)
    @host = host
    @capabilities = host.capabilities
    @queue = []
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question = nil, options: nil, secret: false)
    @host.ask(question, options: options, secret: secret)
  end

  # @rbs question: String?
  # @rbs return: bool
  def confirm(question = nil)
    @host.confirm(question)
  end

  # @rbs message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message = nil, level: :info)
    queue(Riffer::Rig::Events::Notify.new(message, level))
    @host.notify(message, level: level)
  end

  # @rbs label: String?
  # @rbs &block: ^() -> void
  # @rbs return: void
  def progress(label = nil, &block)
    @host.progress(label) { block&.call }
  end

  # @rbs event: (Riffer::Rig::Events::Notify | Riffer::Rig::Events::SessionEnd)
  # @rbs return: void
  def queue(event)
    @queue << event
  end

  # @rbs return: Array[(Riffer::Rig::Events::Notify | Riffer::Rig::Events::SessionEnd)]
  def drain
    queued = @queue
    @queue = []
    queued
  end
end
