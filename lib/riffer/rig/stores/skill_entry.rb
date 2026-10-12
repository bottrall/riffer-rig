# frozen_string_literal: true

class Riffer::Rig::Stores::SkillEntry
  extend Riffer::Rig::Support::TypedValue::Schema #[String]
  include Riffer::Rig::Support::TypedValue #[String]

  typed_value 'skill', :skill

  # @dynamic skill, recorded_at
  attr_reader :skill #: String
  attr_reader :recorded_at #: Time?

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: ::Riffer::Rig::Stores::SkillEntry?
  def self.from_hash(hash)
    skill = hash[:skill]
    return nil unless skill.is_a?(String)

    new(skill: skill, recorded_at: Riffer::Rig::Stores::Timestamp.load(hash[:recorded_at]))
  end

  # @rbs skill: String
  # @rbs recorded_at: Time?
  # @rbs return: void
  def initialize(skill:, recorded_at: nil)
    @skill = skill
    @recorded_at = recorded_at
    freeze
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    super.merge(recorded_at: Riffer::Rig::Stores::Timestamp.dump(@recorded_at)).compact
  end
end
