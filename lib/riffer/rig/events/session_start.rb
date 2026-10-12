# frozen_string_literal: true

class Riffer::Rig::Events::SessionStart
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :session_start, :id, :reason

  # @dynamic id, reason
  attr_reader :id #: String
  attr_reader :reason #: Symbol

  # @rbs id: String
  # @rbs reason: Symbol
  # @rbs return: void
  def initialize(id, reason)
    @id = id
    @reason = reason
    freeze
  end
end
