# frozen_string_literal: true

# riffer runs its before guardrails once per run, just ahead of the first
# request; the Runtime's on_message observer covers the requests after it.
class Riffer::Rig::Runtime::RequestGuardrail < Riffer::Guardrail
  # @rbs @handlers: Riffer::Rig::Runtime::Handlers

  # @rbs handlers: Riffer::Rig::Runtime::Handlers
  # @rbs return: void
  def initialize(handlers:)
    super()
    @handlers = handlers
  end

  # @rbs messages: Array[Riffer::Messages::Base]
  # @rbs context: untyped
  # @rbs return: Riffer::Guardrails::Result
  def process_input(messages, context:)
    verdict = @handlers.before_request(messages)
    return block(verdict.reason) if verdict.is_a?(Riffer::Rig::Runtime::Blocked)

    verdict.equal?(messages) ? pass(messages) : transform(verdict.dup)
  end
end
