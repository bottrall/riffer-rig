# frozen_string_literal: true
# rbs_inline: enabled

# An extension recorded by <tt>Riffer::Rig.extension</tt>: a name, an optional
# Gem::Requirement on riffer-rig, and the block that runs against a Session's
# registrar. The process registry holds these objects; Session.new runs their
# blocks.
class Riffer::Rig::Extension
  attr_reader :name, :requires # : String # : Gem::Requirement?

  # @rbs @block: ^(untyped) -> void

  # : (String, ?requires: String?, &(untyped) -> void) -> void
  def initialize(name, requires: nil, &block)
    @name = name
    @requires = requires && Gem::Requirement.new(requires)
    @block = block
  end

  # : () -> Hash[Symbol, untyped]
  def to_h
    { name: name, requires: requires }
  end

  # : (Riffer::Rig::Registrar) -> void
  def run(registrar)
    @block.call(registrar)
  end
end
