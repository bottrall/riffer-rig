# frozen_string_literal: true

class Riffer::Rig::Events::Event
  # @rbs return: Symbol
  def type
    raise NotImplementedError, "#{self.class.name} must define type"
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    raise NotImplementedError, "#{self.class.name} must define to_h"
  end

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
