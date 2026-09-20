# frozen_string_literal: true

# Holds a named registrar block and its optional riffer-rig version requirement.
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

  # Runs the block against a Runtime's registrar.
  #
  # @rbs registrar: Riffer::Rig::Registrar
  # @rbs return: void
  def run(registrar)
    @block.call(registrar)
  end
end
