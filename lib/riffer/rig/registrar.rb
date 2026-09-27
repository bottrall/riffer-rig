# frozen_string_literal: true

class Riffer::Rig::Registrar
  # @rbs @extension: String
  # @rbs @tools: Hash[String, singleton(Riffer::Tool)]
  # @rbs @prompts: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  # @rbs @commands: Hash[String, Riffer::Rig::Command]

  # @dynamic extension
  attr_reader :extension #: String

  # @rbs extension: String
  # @rbs return: void
  def initialize(extension)
    @extension = extension
    @tools = {}
    @prompts = {}
    @commands = {}
  end

  # @rbs klass: singleton(Riffer::Tool)
  # @rbs return: void
  def tool(klass)
    @tools[klass.identifier] = klass
  end

  # @rbs name: Symbol
  # @rbs &block: (Riffer::Rig::Runtime) -> String?
  # @rbs return: void
  def prompt(name, &block)
    @prompts[name] = block
  end

  # @rbs name: String
  # @rbs description: String
  # @rbs &block: (Riffer::Rig::Command::Context) -> void
  # @rbs return: void
  def command(name, description:, &)
    @commands[name] = Riffer::Rig::Command.new(name, description: description, extension: @extension, &)
  end

  # @rbs return: Hash[String, singleton(Riffer::Tool)]
  def tools
    @tools.dup
  end

  # @rbs return: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  def prompts
    @prompts.dup
  end

  # @rbs return: Hash[String, Riffer::Rig::Command]
  def commands
    @commands.dup
  end

  # @rbs return: Array[String]
  def registrations
    [
      *@tools.keys.map { |identifier| "tool #{identifier}" },
      *@prompts.keys.map { |name| "prompt section #{name}" },
      *@commands.keys.map { |name| "command #{name}" }
    ]
  end
end
