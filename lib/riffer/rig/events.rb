# frozen_string_literal: true

require 'securerandom'

# The rig-level events every host renders alongside riffer's StreamEvents.
# They are immutable Data objects; each has +to_h+ — with the type folded in, so
# the headless host can print every record verbatim as NDJSON — and +type+, the
# snake_case form of its class name.
#
#   Riffer::Rig::Events.SessionStart.new(id: '0198...', reason: :new).type
#   # => :session_start
#
#   Riffer::Rig::Events.TurnEnd.new(stop_reason: :completed, usage: nil).to_h
#   # => { stop_reason: :completed, usage: nil, type: :turn_end }
#
# The extra methods are attached with string +class_eval+: inside a literal
# method body Steep resolves +self+ to the enclosing module, where the Data
# members don't exist, and a +define_method+ block body hides them the same way.
# The member types themselves are checked — they come from the +#: Type+
# comments on the symbols below — as is every call site.
module Riffer::Rig::Events
  extend self

  SessionStart = Data.define(
    :id, #: String
    :reason #: Symbol
  )

  SessionEnd = Data.define(
    :reason #: Symbol
  )

  CommandOutput = Data.define(
    :command, #: String
    :text #: String
  )

  SkillActivated = Data.define(
    :name #: String
  )

  Notify = Data.define(
    :message, #: String?
    :level #: Symbol
  )

  TurnEnd = Data.define(
    :stop_reason, #: Symbol
    :usage #: ::Riffer::Providers::TokenUsage?
  )

  SessionStart.class_eval <<~RUBY, __FILE__, __LINE__ + 1
    def type = :session_start

    def to_h = super().merge(type: :session_start)
  RUBY

  SessionEnd.class_eval <<~RUBY, __FILE__, __LINE__ + 1
    def type = :session_end

    def to_h = super().merge(type: :session_end)
  RUBY

  CommandOutput.class_eval <<~RUBY, __FILE__, __LINE__ + 1
    def type = :command_output

    def to_h = super().merge(type: :command_output)
  RUBY

  SkillActivated.class_eval <<~RUBY, __FILE__, __LINE__ + 1
    def type = :skill_activated

    def to_h = super().merge(type: :skill_activated)
  RUBY

  Notify.class_eval <<~RUBY, __FILE__, __LINE__ + 1
    def type = :notify

    def to_h = super().merge(type: :notify)
  RUBY

  TurnEnd.class_eval <<~RUBY, __FILE__, __LINE__ + 1
    def cost = usage&.cost

    def type = :turn_end

    def to_h = super().merge(type: :turn_end)
  RUBY
end
