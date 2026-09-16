# frozen_string_literal: true

# An extension recorded by <tt>Riffer::Rig.extension</tt>: a name, an optional
# Gem::Requirement on riffer-rig, and the block that runs against a Runtime's
# registrar. The process registry holds these objects; Runtime.new runs their
# blocks.
class Riffer::Rig::Extension
  # @rbs @name: String
  # @rbs @requires: Gem::Requirement?
  # @rbs @block: ^(::Riffer::Rig::Registrar) -> void

  # @dynamic name, requires
  attr_reader :name #: String
  attr_reader :requires #: Gem::Requirement?

  # @rbs name: String
  # @rbs requires: String?
  # @rbs &block: (::Riffer::Rig::Registrar) -> void
  # @rbs return: void
  def initialize(name, requires: nil, &block)
    @name = name
    @requires = requires && Gem::Requirement.new(requires)
    @block = block
  end

  # @rbs registrar: Riffer::Rig::Registrar
  # @rbs return: void
  def run(registrar)
    @block.call(registrar)
  end
end
