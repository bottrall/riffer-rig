# frozen_string_literal: true

class Riffer::Rig::Stores::ModelEntry
  TYPE = 'model' #: String

  extend Riffer::Rig::Support::TypedValue::Schema #[String]
  include Riffer::Rig::Support::TypedValue #[String]

  typed_value TYPE, :model

  # @dynamic model
  attr_reader :model #: String

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: ::Riffer::Rig::Stores::ModelEntry?
  def self.from_hash(hash)
    model = hash[:model]
    return nil unless model.is_a?(String)

    new(model: model)
  end

  # @rbs model: String
  # @rbs return: void
  def initialize(model:)
    @model = model
    freeze
  end
end
