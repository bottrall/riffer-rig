# frozen_string_literal: true

class Riffer::Rig::Command::Context
  # @rbs @command: String
  # @rbs @emit: ^(Riffer::Rig::Events::Event) -> void
  # @rbs @turn: ^(String) -> void

  # @dynamic args, runtime, host, settings
  attr_reader :args #: String
  attr_reader :runtime #: Riffer::Rig::Runtime
  attr_reader :host #: Riffer::Rig::Hosts::Base
  attr_reader :settings #: Hash[Symbol, untyped]

  # @rbs command: String
  # @rbs args: String
  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs host: Riffer::Rig::Hosts::Base
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs emit: ^(Riffer::Rig::Events::Event) -> void
  # @rbs turn: ^(String) -> void
  # @rbs return: void
  def initialize(command, args, runtime:, host:, settings:, emit:, turn:)
    @command = command
    @args = args
    @runtime = runtime
    @host = host
    @settings = settings
    @emit = emit
    @turn = turn
    freeze
  end

  # @rbs text: String
  # @rbs return: nil
  def say(text)
    @emit.call(Riffer::Rig::Events::CommandOutput.new(@command, text))
    nil
  end

  # @rbs text: String
  # @rbs return: nil
  def prompt(text)
    @turn.call(text)
    nil
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question = nil, options: nil, secret: false)
    return unless host.capabilities.include?(:ask)

    host.ask(question, options: options, secret: secret)
  end

  # @rbs question: String?
  # @rbs return: bool
  def confirm(question = nil)
    return false unless host.capabilities.include?(:confirm)

    host.confirm(question)
  end
end
