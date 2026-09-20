# frozen_string_literal: true

class Riffer::Rig::Hosts::Mirror < Riffer::Rig::Hosts::Base
  # @rbs @host: Riffer::Rig::Hosts::Base
  # @rbs @queue: Array[Riffer::Rig::Events::Event]

  # @dynamic capabilities
  attr_reader :capabilities #: Set[Symbol]

  # @rbs host: Riffer::Rig::Hosts::Base
  # @rbs return: void
  def initialize(host)
    super()
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
  # @rbs &block: ? () -> void
  # @rbs return: void
  def progress(label = nil, &block)
    @host.progress(label) { block&.call }
  end

  # @rbs event: Riffer::Rig::Events::Event
  # @rbs return: void
  def queue(event)
    @queue << event
  end

  # @rbs return: Array[Riffer::Rig::Events::Event]
  def drain
    queued = @queue
    @queue = []
    queued
  end
end
