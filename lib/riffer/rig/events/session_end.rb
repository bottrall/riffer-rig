# frozen_string_literal: true

class Riffer::Rig::Events::SessionEnd
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :session_end, :reason

  # @dynamic reason
  attr_reader :reason #: Symbol

  # @rbs reason: Symbol
  # @rbs return: void
  def initialize(reason)
    @reason = reason
    freeze
  end
end
