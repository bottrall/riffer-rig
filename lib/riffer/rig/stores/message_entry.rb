# frozen_string_literal: true

class Riffer::Rig::Stores::MessageEntry
  TYPE = 'message' #: String

  extend Riffer::Rig::Support::TypedValue::Schema #[String]
  include Riffer::Rig::Support::TypedValue #[String]

  typed_value TYPE, :message

  # @dynamic message
  attr_reader :message #: Hash[Symbol, untyped]

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: ::Riffer::Rig::Stores::MessageEntry?
  def self.from_hash(hash)
    message = hash[:message]
    return nil unless message.is_a?(Hash)

    new(message: message)
  end

  # @rbs message: Hash[Symbol, untyped]
  # @rbs return: void
  def initialize(message:)
    @message = message
    freeze
  end
end
