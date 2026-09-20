# frozen_string_literal: true

class Riffer::Rig::Registrar
  # @rbs @tools: Array[singleton(Riffer::Tool)]

  # @rbs return: void
  def initialize
    @tools = []
  end

  # @rbs klass: singleton(Riffer::Tool)
  # @rbs return: void
  def tool(klass)
    @tools << klass
  end

  # @rbs return: Array[singleton(Riffer::Tool)]
  def tools
    @tools.dup
  end
end
