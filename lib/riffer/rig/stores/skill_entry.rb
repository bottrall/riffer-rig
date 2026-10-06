# frozen_string_literal: true

class Riffer::Rig::Stores::SkillEntry
  TYPE = 'skill' #: String

  include Riffer::Rig::Support::Equatable

  # @dynamic skill
  attr_reader :skill #: String

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: ::Riffer::Rig::Stores::SkillEntry?
  def self.from_hash(hash)
    skill = hash[:skill]
    return nil unless skill.is_a?(String)

    new(skill: skill)
  end

  # @rbs skill: String
  # @rbs return: void
  def initialize(skill:)
    @skill = skill
    freeze
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: TYPE, skill: @skill }
  end
end
