# frozen_string_literal: true
# rbs_inline: enabled

# The per-Session registrar extension blocks run against. Seams are added one
# at a time; today only #tool exists.
class Riffer::Rig::Registrar
  # @rbs @tools: Array[singleton(Riffer::Tool)]

  # : () -> void
  def initialize
    @tools = []
  end

  # : (singleton(Riffer::Tool)) -> void
  def tool(klass)
    @tools << klass
  end

  # : () -> Array[singleton(Riffer::Tool)]
  def tools
    @tools.dup
  end
end
