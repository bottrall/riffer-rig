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
      hash = { type: type } #: Hash[Symbol, untyped]
      instance_variables.each { |name| hash[name.to_s.delete_prefix('@').to_sym] = instance_variable_get(name) }
      hash
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

  class SessionStart < Event
    # @dynamic id, reason
    attr_reader :id #: String
    attr_reader :reason #: Symbol

    # @rbs id: String
    # @rbs reason: Symbol
    # @rbs return: void
    def initialize(id, reason)
      super()
      @id = id
      @reason = reason
      freeze
    end

    # @rbs return: Symbol
    def type
      :session_start
    end
  end

  class SessionEnd < Event
    # @dynamic reason
    attr_reader :reason #: Symbol

    # @rbs reason: Symbol
    # @rbs return: void
    def initialize(reason)
      super()
      @reason = reason
      freeze
    end

    # @rbs return: Symbol
    def type
      :session_end
    end
  end

  class CommandOutput < Event
    # @dynamic command, text
    attr_reader :command #: String
    attr_reader :text #: String

    # @rbs command: String
    # @rbs text: String
    # @rbs return: void
    def initialize(command, text)
      super()
      @command = command
      @text = text
      freeze
    end

    # @rbs return: Symbol
    def type
      :command_output
    end
  end

  class SkillActivated < Event
    # @dynamic name
    attr_reader :name #: String

    # @rbs name: String
    # @rbs return: void
    def initialize(name)
      super()
      @name = name
      freeze
    end

    # @rbs return: Symbol
    def type
      :skill_activated
    end
  end

  class Notify < Event
    # @dynamic message, level
    attr_reader :message #: String?
    attr_reader :level #: Symbol

    # @rbs message: String?
    # @rbs level: Symbol
    # @rbs return: void
    def initialize(message, level)
      super()
      @message = message
      @level = level
      freeze
    end

    # @rbs return: Symbol
    def type
      :notify
    end
  end

  class TurnEnd < Event
    # @dynamic stop_reason, usage
    attr_reader :stop_reason #: Symbol
    attr_reader :usage #: ::Riffer::Providers::TokenUsage?

    # @rbs stop_reason: Symbol
    # @rbs usage: ::Riffer::Providers::TokenUsage?
    # @rbs return: void
    def initialize(stop_reason, usage)
      super()
      @stop_reason = stop_reason
      @usage = usage
      freeze
    end

    # The USD cost of the turn's usage, or nil when pricing is missing.
    #
    # @rbs return: Float?
    def cost
      usage&.cost
    end

    # @rbs return: Symbol
    def type
      :turn_end
    end
  end
end
