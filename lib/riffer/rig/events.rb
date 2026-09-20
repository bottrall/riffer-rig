# frozen_string_literal: true

# The rig-level events every host renders alongside riffer's StreamEvents.
# They are frozen value objects; each has +to_h+ — with the type folded in, so
# the headless host can print every record verbatim as NDJSON — and +type+, the
# snake_case form of its class name.
#
#   Riffer::Rig::Events::SessionStart.new(id: '0198...', reason: :new).type
#   # => :session_start
#
#   Riffer::Rig::Events::TurnEnd.new(stop_reason: :completed, usage: nil).to_h
#   # => { stop_reason: :completed, usage: nil, type: :turn_end }
module Riffer::Rig::Events
  # Frozen value object: plain readers, a +type+ (the snake_case event name),
  # and a +to_h+ with the type folded in.
  class Event
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
end
