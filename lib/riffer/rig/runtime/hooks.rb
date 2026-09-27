# frozen_string_literal: true

class Riffer::Rig::Runtime::Hooks
  # @rbs @hooks: Hash[Symbol, Array[^(Riffer::Rig::Events::Event | ::Riffer::StreamEvents::Base) -> untyped]]
  # @rbs @host: Riffer::Rig::Hosts::Base

  # @rbs hooks: Hash[Symbol, Array[^(Riffer::Rig::Events::Event | ::Riffer::StreamEvents::Base) -> untyped]]
  # @rbs host: Riffer::Rig::Hosts::Base
  # @rbs return: void
  def initialize(hooks, host)
    @hooks = hooks
    @host = host
  end

  # @rbs name: Symbol
  # @rbs event: Riffer::Rig::Events::Event | ::Riffer::StreamEvents::Base
  # @rbs return: void
  def observe(name, event)
    @hooks.fetch(name).each { |hook| call(name, hook, event) }
  end

  # @rbs text: String
  # @rbs return: String | Riffer::Rig::Runtime::Blocked
  def before_prompt(text)
    accepts = ->(value) { value.is_a?(String) }
    announce(veto(:before_prompt, text, accepts) { |current| Riffer::Rig::Events::BeforePrompt.new(current) })
  end

  # @rbs tool: String
  # @rbs args: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped] | Riffer::Rig::Runtime::Blocked
  def before_tool_call(tool, args)
    accepts = ->(value) { value.is_a?(Hash) }
    veto(:before_tool_call, args, accepts) { |current| Riffer::Rig::Events::BeforeToolCall.new(tool, current) }
  end

  # @rbs messages: Array[::Riffer::Messages::Base]
  # @rbs return: Array[::Riffer::Messages::Base] | Riffer::Rig::Runtime::Blocked
  def before_request(messages)
    accepts = ->(value) { value.is_a?(Array) && value.all?(::Riffer::Messages::Base) }
    announce(veto(:before_request, messages, accepts) { |current| Riffer::Rig::Events::BeforeRequest.new(current) })
  end

  private

  # @rbs name: Symbol
  # @rbs payload: untyped
  # @rbs accepts: ^(untyped) -> bool
  # @rbs &: (untyped) -> Riffer::Rig::Events::Event
  # @rbs return: untyped
  def veto(name, payload, accepts)
    @hooks.fetch(name).reduce(payload) do |current, hook|
      result = call(name, hook, yield(current))
      verdict, reason = result
      break Riffer::Rig::Runtime::Blocked.new(reason&.to_s || "blocked by a #{name} hook") if verdict == :block

      accepts.call(result) ? result : current
    end
  end

  # @rbs outcome: untyped
  # @rbs return: untyped
  def announce(outcome)
    @host.notify(outcome.reason, level: :warning) if outcome.is_a?(Riffer::Rig::Runtime::Blocked)
    outcome
  end

  # @rbs name: Symbol
  # @rbs hook: ^(Riffer::Rig::Events::Event | ::Riffer::StreamEvents::Base) -> untyped
  # @rbs event: Riffer::Rig::Events::Event | ::Riffer::StreamEvents::Base
  # @rbs return: untyped
  def call(name, hook, event)
    hook.call(event)
  rescue StandardError => e
    @host.notify("#{name} hook failed: #{e.message}", level: :error)
    nil
  end
end
