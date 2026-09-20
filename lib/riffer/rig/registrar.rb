# frozen_string_literal: true

# Collects what extension blocks register for one Runtime.
class Riffer::Rig::Registrar
  # @rbs @tools: Array[singleton(Riffer::Tool)]

  # @rbs return: void
  def initialize
    @tools = []
  end

  # Registers a Riffer::Tool class with the Runtime.
  #
  # @rbs klass: singleton(Riffer::Tool)
  # @rbs return: void
  def tool(klass)
    @tools << klass
  end

  # Returns a copy of the registered tool classes.
  #
  # @rbs return: Array[singleton(Riffer::Tool)]
  def tools
    @tools.dup
  end
end
