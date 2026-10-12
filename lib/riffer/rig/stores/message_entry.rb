# frozen_string_literal: true

class Riffer::Rig::Stores::MessageEntry
  extend Riffer::Rig::Support::TypedValue::Schema #[String]
  include Riffer::Rig::Support::TypedValue #[String]
  include Riffer::Rig::Stores::Stamped

  typed_value 'message', :message, :recorded_at

  # @dynamic message, recorded_at
  attr_reader :message #: Hash[Symbol, untyped]
  attr_reader :recorded_at #: String?

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: ::Riffer::Rig::Stores::MessageEntry?
  def self.from_hash(hash)
    message = hash[:message]
    return nil unless message.is_a?(Hash)

    new(message: message, recorded_at: Riffer::Rig::Stores::Timestamp.dump(Riffer::Rig::Stores::Timestamp.load(hash[:recorded_at])))
  end

  # @rbs message: Hash[Symbol, untyped]
  # @rbs recorded_at: String?
  # @rbs return: void
  def initialize(message:, recorded_at: nil)
    @message = message
    @recorded_at = recorded_at
    freeze
  end
end
