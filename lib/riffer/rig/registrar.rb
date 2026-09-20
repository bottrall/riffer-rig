# frozen_string_literal: true

class Riffer::Rig::Registrar
  # @rbs @tools: Array[singleton(Riffer::Tool)]
  # @rbs @prompts: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]

  # @rbs return: void
  def initialize
    @tools = []
    @prompts = {}
  end

  # @rbs klass: singleton(Riffer::Tool)
  # @rbs return: void
  def tool(klass)
    @tools << klass
  end

  # @rbs name: Symbol
  # @rbs &block: (Riffer::Rig::Runtime) -> String?
  # @rbs return: void
  def prompt(name, &block)
    @prompts[name] = block
  end

  # @rbs return: Array[singleton(Riffer::Tool)]
  def tools
    @tools.dup
  end

  # @rbs return: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  def prompts
    @prompts.dup
  end
end
