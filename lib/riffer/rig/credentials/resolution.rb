# frozen_string_literal: true

class Riffer::Rig::Credentials::Resolution
  # @dynamic values, missing
  attr_reader :values #: Hash[Symbol, String]
  attr_reader :missing #: Array[Symbol]

  # @rbs values: Hash[Symbol, String]
  # @rbs missing: Array[Symbol]
  # @rbs return: void
  def initialize(values:, missing:)
    @values = values.freeze
    @missing = missing.freeze
    freeze
  end
end
