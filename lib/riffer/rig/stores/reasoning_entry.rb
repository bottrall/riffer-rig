# frozen_string_literal: true

class Riffer::Rig::Stores::ReasoningEntry
  extend Riffer::Rig::Support::TypedValue::Schema #[String]
  include Riffer::Rig::Support::TypedValue #[String]
  include Riffer::Rig::Stores::Stamped

  typed_value 'reasoning', :reasoning, :recorded_at

  # @dynamic reasoning, recorded_at
  attr_reader :reasoning #: String
  attr_reader :recorded_at #: String?

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: ::Riffer::Rig::Stores::ReasoningEntry?
  def self.from_hash(hash)
    reasoning = hash[:reasoning]
    return nil unless reasoning.is_a?(String)

    new(reasoning: reasoning, recorded_at: Riffer::Rig::Stores::Timestamp.dump(Riffer::Rig::Stores::Timestamp.load(hash[:recorded_at])))
  end

  # @rbs reasoning: String
  # @rbs recorded_at: String?
  # @rbs return: void
  def initialize(reasoning:, recorded_at: nil)
    @reasoning = reasoning
    @recorded_at = recorded_at
    freeze
  end
end
