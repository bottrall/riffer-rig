# frozen_string_literal: true

class Riffer::Rig::Stores::ModelEntry
  extend Riffer::Rig::Support::TypedValue::Schema #[String]
  include Riffer::Rig::Support::TypedValue #[String]
  include Riffer::Rig::Stores::Stamped

  typed_value 'model', :model, :recorded_at

  # @dynamic model, recorded_at
  attr_reader :model #: String
  attr_reader :recorded_at #: String?

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: ::Riffer::Rig::Stores::ModelEntry?
  def self.from_hash(hash)
    model = hash[:model]
    return nil unless model.is_a?(String)

    new(model: model, recorded_at: Riffer::Rig::Stores::Timestamp.dump(Riffer::Rig::Stores::Timestamp.load(hash[:recorded_at])))
  end

  # @rbs model: String
  # @rbs recorded_at: String?
  # @rbs return: void
  def initialize(model:, recorded_at: nil)
    @model = model
    @recorded_at = recorded_at
    freeze
  end
end
