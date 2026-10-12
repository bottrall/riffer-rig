# frozen_string_literal: true

class Riffer::Rig::Events::Notify
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :notify, :message, :level

  # @dynamic message, level
  attr_reader :message #: String?
  attr_reader :level #: Symbol

  # @rbs message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def initialize(message, level)
    @message = message
    @level = level
    freeze
  end
end
