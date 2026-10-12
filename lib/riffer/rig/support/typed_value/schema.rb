# frozen_string_literal: true

# @rbs generic T
module Riffer::Rig::Support::TypedValue::Schema
  # @dynamic type, attributes
  attr_reader :type #: T
  attr_reader :attributes #: Array[Symbol]

  # @rbs type: T
  # @rbs *attributes: Symbol
  # @rbs return: void
  def typed_value(type, *attributes)
    @type = type
    @attributes = attributes.freeze
  end
end
