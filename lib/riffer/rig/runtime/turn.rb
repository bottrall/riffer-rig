# frozen_string_literal: true

class Riffer::Rig::Runtime::Turn
  # Per turn, so a job that starts jobs cannot keep a turn alive forever.
  MAX_JOB_CONTINUATIONS = 5 #: Integer

  # @rbs @yielder: Enumerator::Yielder
  # @rbs @host: Riffer::Rig::Hosts::Mirror
  # @rbs @abort: Riffer::Rig::Runtime::Abort
  # @rbs @agent: ^() -> Riffer::Agent
  # @rbs @hooks: ^() -> Riffer::Rig::Runtime::Hooks
  # @rbs @continuation: ^() -> Enumerator[::Riffer::StreamEvents::Base, Riffer::Agent::Response]?
  # @rbs @deliver: ^(Riffer::Messages::Base) -> void
  # @rbs @draft: Array[String]

  # @rbs yielder: Enumerator::Yielder
  # @rbs host: Riffer::Rig::Hosts::Mirror
  # @rbs abort: Riffer::Rig::Runtime::Abort
  # @rbs agent: ^() -> Riffer::Agent
  # @rbs hooks: ^() -> Riffer::Rig::Runtime::Hooks
  # @rbs continuation: ^() -> Enumerator[::Riffer::StreamEvents::Base, Riffer::Agent::Response]?
  # @rbs deliver: ^(Riffer::Messages::Base) -> void
  # @rbs return: void
  def initialize(yielder, host:, abort:, agent:, hooks:, continuation:, deliver:)
    @yielder = yielder
    @host = host
    @abort = abort
    @agent = agent
    @hooks = hooks
    @continuation = continuation
    @deliver = deliver
    @draft = []
  end

  # @rbs session_start: Riffer::Rig::Events::SessionStart?
  # @rbs &: () -> Enumerator[::Riffer::StreamEvents::Base, Riffer::Agent::Response]
  # @rbs return: Riffer::Agent::Response
  def run(session_start, &)
    if session_start
      @hooks.call.observe(:session_start, session_start)
      @yielder << session_start
    end
    drain
    response = @abort.window do
      stream = Thread.handle_interrupt(Riffer::Rig::Runtime::Abort::SHIELD, &)
      continued(relay(stream), MAX_JOB_CONTINUATIONS)
    end
    response ||= aborted
    stop_reason = Riffer::Rig::Runtime::StopReason.of(response.outcome)
    turn_end = Riffer::Rig::Events::TurnEnd.new(stop_reason, response.token_usage)
    @hooks.call.observe(:turn_end, turn_end)
    drain
    @yielder << turn_end
    response
  end

  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: void
  def forward(event)
    @yielder << event
    # Mid-turn notifies (a failing hook, a blocked request) reach the stream
    # next to the event that raised them, not at the next turn.
    drain
  end

  # @rbs return: void
  def clear_draft
    @draft = []
  end

  private

  # @rbs stream: Enumerator[Riffer::StreamEvents::Base, Riffer::Agent::Response]
  # @rbs return: Riffer::Agent::Response
  def relay(stream)
    stream.each do |event|
      Thread.handle_interrupt(Riffer::Rig::Runtime::Abort::SHIELD) { pass_through(event) }
    end
  end

  # @rbs response: Riffer::Agent::Response
  # @rbs remaining: Integer
  # @rbs return: Riffer::Agent::Response
  def continued(response, remaining)
    return response unless remaining.positive? && response.outcome.reason == :completed && steps_left?(response)

    stream = Thread.handle_interrupt(Riffer::Rig::Runtime::Abort::SHIELD) { @continuation.call }
    return response unless stream

    continued(combined(response, relay(stream)), remaining - 1)
  end

  # @rbs response: Riffer::Agent::Response
  # @rbs return: bool
  def steps_left?(response)
    max_steps = @agent.call.config.max_steps
    # Upstream candidate: riffer counts a run's steps from the last user-class
    # message, so a continuation cannot be handed what the turn has left and
    # starts on the full limit.
    max_steps.nil? || response.steps < max_steps
  end

  # @rbs earlier: Riffer::Agent::Response
  # @rbs later: Riffer::Agent::Response
  # @rbs return: Riffer::Agent::Response
  def combined(earlier, later)
    Riffer::Agent::Response.new(
      later.content,
      outcome: later.outcome,
      tripwire: later.tripwire,
      modifications: earlier.modifications + later.modifications,
      reasoning: later.reasoning,
      structured_output: later.structured_output,
      messages: later.messages,
      token_usage: Riffer::Rig::Runtime::Usage.total([earlier.token_usage, later.token_usage]),
      steps: earlier.steps + later.steps
    )
  end

  # @rbs return: Riffer::Agent::Response
  def aborted
    session = @agent.call.session
    # The abort unwinds riffer's run loop from outside, so what riffer does for
    # an interrupt it raises itself is done here.
    session.discard_pending_tool_calls
    text = @draft.join
    # Silent, then delivered by hand: the on_message observer interrupts a
    # cancelled turn with a throw, and riffer's catch is gone by now.
    @deliver.call(session.add(Riffer::Messages::Assistant.new(text), silent: true)) if text.match?(/\S/)
    cancelled = Riffer::Rig::Runtime::StopReason::INTERRUPT_CANCELLED
    pass_through(Riffer::StreamEvents::Interrupt.new(reason: cancelled))
    Riffer::Agent::Response.new(
      text,
      outcome: Riffer::Agent::Outcome.new(reason: :interrupted, detail: cancelled.to_s),
      messages: session.messages.dup.freeze
    )
  end

  # @rbs event: ::Riffer::StreamEvents::Base
  # @rbs return: void
  def pass_through(event)
    @draft << event.content if event.is_a?(Riffer::StreamEvents::TextDelta)
    @hooks.call.observe(:stream, event)
    forward(event)
  end

  # @rbs return: void
  def drain
    @host.drain.each { |queued| @yielder << queued }
  end
end
