# frozen_string_literal: true

# @rbs generic T
# @rbs module-self Riffer::Rig::Support::_TypedValue[T]
module Riffer::Rig::Support::TypedValue
  include Riffer::Rig::Support::Equatable

  # @rbs return: T
  def type
    self.class.type
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { type: type }.merge(self.class.attributes.to_h { |name| [name, public_send(name)] })
  end
end
