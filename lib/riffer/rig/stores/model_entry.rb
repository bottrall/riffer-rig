# frozen_string_literal: true

class Riffer::Rig::Stores::ModelEntry
  TYPE = 'model' #: String

  include Riffer::Rig::Support::Equatable

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

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: TYPE, model: @model }
  end
end
