# frozen_string_literal: true

class Riffer::Rig::Events::SkillActivated
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :skill_activated, :name

  # @dynamic name
  attr_reader :name #: String

  # @rbs name: String
  # @rbs return: void
  def initialize(name)
    @name = name
    freeze
  end
end
