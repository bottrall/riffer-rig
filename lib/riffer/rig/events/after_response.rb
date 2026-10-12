# frozen_string_literal: true

class Riffer::Rig::Events::AfterResponse
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :after_response, :message

  # @dynamic message
  attr_reader :message #: ::Riffer::Messages::Assistant

  # @rbs message: ::Riffer::Messages::Assistant
  # @rbs return: void
  def initialize(message)
    @message = message
    freeze
  end
end
