# frozen_string_literal: true

require 'json'

class Riffer::Rig::Runtime::ToolRuntime < Riffer::Tools::Runtime
  # @rbs @hooks: Riffer::Rig::Runtime::Hooks
  # @rbs @emit: ^(Riffer::Rig::Events::_Event) -> void
  # @rbs @clock: ^() -> Float

  # @rbs hooks: Riffer::Rig::Runtime::Hooks
  # @rbs emit: ^(Riffer::Rig::Events::_Event) -> void
  # @rbs clock: ^() -> Float
  # @rbs return: void
  def initialize(hooks, emit:, clock:)
    # Sequential, so hooks never run concurrently.
    super(runner: Riffer::Runner::Sequential.new)
    @hooks = hooks
    @emit = emit
    @clock = clock
  end

  # @rbs tool_calls: Array[Riffer::Messages::Assistant::ToolCall]
  # @rbs tools: Array[singleton(Riffer::Tool)]
  # @rbs context: Riffer::Agent::Context?
  # @rbs assistant_message: Riffer::Messages::Assistant?
  # @rbs tags: Hash[String, String]
  # @rbs return: Array[[Riffer::Messages::Assistant::ToolCall, Riffer::Tools::Response]]
  def execute(tool_calls, tools:, context:, assistant_message: nil, tags: {})
    Thread.handle_interrupt(Riffer::Rig::Runtime::Abort::SHIELD) { super }
  end

  private

  # @rbs tool_call: Riffer::Messages::Assistant::ToolCall
  # @rbs tools: Array[singleton(Riffer::Tool)]
  # @rbs context: Riffer::Agent::Context?
  # @rbs assistant_message: Riffer::Messages::Assistant?
  # @rbs return: Riffer::Tools::Response
  def dispatch_tool_call(tool_call, tools:, context:, assistant_message: nil)
    args = parse_arguments(tool_call.arguments)
    return never_ran(tool_call, {}, super) unless args.is_a?(Hash)

    verdict = @hooks.before_tool_call(tool_call.call_id, tool_call.name, args, @clock.call)
    if verdict.is_a?(Riffer::Rig::Runtime::Blocked)
      return never_ran(tool_call, args, Riffer::Tools::Response.error(verdict.reason, type: :blocked))
    end

    call = verdict.equal?(args) ? tool_call : replace_arguments(tool_call, verdict)
    started = @clock.call
    @emit.call(Riffer::Rig::Events::BeforeToolCall.new(tool_call.call_id, tool_call.name, verdict, started))
    response = super(call, tools: tools, context: context, assistant_message: assistant_message)
    finished = @clock.call
    finish(
      Riffer::Rig::Events::AfterToolCall.new(
        tool_call.call_id, tool_call.name, verdict, response, finished, finished - started
      )
    )
  rescue JSON::ParserError
    never_ran(tool_call, {}, super)
  end

  # @rbs tool_call: Riffer::Messages::Assistant::ToolCall
  # @rbs args: Hash[Symbol, untyped]
  # @rbs response: Riffer::Tools::Response
  # @rbs return: Riffer::Tools::Response
  def never_ran(tool_call, args, response)
    finish(Riffer::Rig::Events::AfterToolCall.new(tool_call.call_id, tool_call.name, args, response, @clock.call, 0.0))
  end

  # @rbs event: Riffer::Rig::Events::AfterToolCall
  # @rbs return: Riffer::Tools::Response
  def finish(event)
    @hooks.observe(:after_tool_call, event)
    @emit.call(event)
    event.result
  end

  # @rbs tool_call: Riffer::Messages::Assistant::ToolCall
  # @rbs args: Hash[Symbol, untyped]
  # @rbs return: Riffer::Messages::Assistant::ToolCall
  def replace_arguments(tool_call, args)
    Riffer::Messages::Assistant::ToolCall.new(call_id: tool_call.call_id, name: tool_call.name, arguments: args.to_json)
  end
end
