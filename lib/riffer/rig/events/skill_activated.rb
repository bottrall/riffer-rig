# frozen_string_literal: true

class Riffer::Rig::Events::SkillActivated < Riffer::Rig::Events::Event
  # @dynamic name
  attr_reader :name #: String

  # @rbs name: String
  # @rbs return: void
  def initialize(name)
    super()
    @name = name
    freeze
  end

  # @rbs return: Symbol
  def type
    :skill_activated
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type, name: name }
  end
end
