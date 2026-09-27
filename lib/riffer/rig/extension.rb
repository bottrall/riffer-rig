# frozen_string_literal: true

class Riffer::Rig::Extension
  class RequirementError < StandardError; end

  # @rbs @name: String
  # @rbs @requires: Gem::Requirement?
  # @rbs @mismatch: RequirementError?
  # @rbs @block: ^(::Riffer::Rig::Registrar) -> void

  # @dynamic name, requires, mismatch
  attr_reader :name #: String
  attr_reader :requires #: Gem::Requirement?
  attr_reader :mismatch #: RequirementError?

  # @rbs name: String
  # @rbs requires: String?
  # @rbs &block: (::Riffer::Rig::Registrar) -> void
  # @rbs return: void
  def initialize(name, requires: nil, &block)
    @name = name
    @requires = requires && Gem::Requirement.new(requires)
    @mismatch = check(@requires)
    @block = block
  end

  # @rbs registrar: Riffer::Rig::Registrar
  # @rbs return: void
  def run(registrar)
    @block.call(registrar)
  end

  private

  # @rbs requirement: Gem::Requirement?
  # @rbs return: RequirementError?
  def check(requirement)
    return if requirement.nil? || requirement.satisfied_by?(Gem::Version.new(Riffer::Rig::VERSION))

    RequirementError.new("extension #{@name} requires riffer-rig #{requirement}, found #{Riffer::Rig::VERSION}")
  end
end
