# frozen_string_literal: true

class Riffer::Rig::Stores::ModelEntry
  extend Riffer::Rig::Support::TypedValue::Schema #[String]
  include Riffer::Rig::Support::TypedValue #[String]

  typed_value 'model', :model

  # @dynamic model, recorded_at
  attr_reader :model #: String
  attr_reader :recorded_at #: Time?

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: ::Riffer::Rig::Stores::ModelEntry?
  def self.from_hash(hash)
    model = hash[:model]
    return nil unless model.is_a?(String)

    new(model: model, recorded_at: Riffer::Rig::Stores::Timestamp.load(hash[:recorded_at]))
  end

  # @rbs model: String
  # @rbs recorded_at: Time?
  # @rbs return: void
  def initialize(model:, recorded_at: nil)
    @model = model
    @recorded_at = recorded_at
    freeze
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    super.merge(recorded_at: Riffer::Rig::Stores::Timestamp.dump(@recorded_at)).compact
  end
end
