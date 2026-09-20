# frozen_string_literal: true

# Defines what every rig-level event shares: a type, a hash form and value
# equality.
class Riffer::Rig::Events::Event
  # Returns the snake_case event name.
  #
  # @rbs return: Symbol
  def type
    raise NotImplementedError, "#{self.class.name} must define type"
  end

  # Returns the event's fields with the type folded in, so a record serializes
  # verbatim as NDJSON.
  #
  # @rbs return: Hash[Symbol, untyped]
  def to_h
    raise NotImplementedError, "#{self.class.name} must define to_h"
  end

  # Compares events by class and fields.
  #
  # @rbs other: untyped
  # @rbs return: bool
  def ==(other)
    other.class == self.class && other.to_h == to_h
  end

  # Hashes by class and fields, matching #==.
  #
  # @rbs return: Integer
  def hash
    [self.class, to_h].hash
  end

  # Matches #==, so equal events collide as Hash keys.
  #
  # @rbs other: untyped
  # @rbs return: bool
  def eql?(other)
    self == other
  end
end
