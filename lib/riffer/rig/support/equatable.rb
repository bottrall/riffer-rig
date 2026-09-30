# frozen_string_literal: true

# @rbs module-self Riffer::Rig::Support::_ToH
module Riffer::Rig::Support::Equatable
  # @rbs other: untyped
  # @rbs return: bool
  def ==(other)
    other.class == self.class && other.to_h == to_h
  end

  # @rbs return: Integer
  def hash
    [self.class, to_h].hash
  end

  # @rbs other: untyped
  # @rbs return: bool
  def eql?(other)
    self == other
  end
end
