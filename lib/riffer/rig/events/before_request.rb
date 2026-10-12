# frozen_string_literal: true

class Riffer::Rig::Events::BeforeRequest
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :before_request, :messages

  # @dynamic messages
  attr_reader :messages #: Array[::Riffer::Messages::Base]

  # @rbs messages: Array[::Riffer::Messages::Base]
  # @rbs return: void
  def initialize(messages)
    @messages = messages.dup.freeze
    freeze
  end
end
