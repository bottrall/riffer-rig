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
    tool_calls.each do |tool_call|
      @emit.call(Riffer::Rig::Events::ToolDispatched.new(tool_call.call_id, tool_call.name, @clock.call))
    end
    super
  end

  # @rbs tool_call: Riffer::Messages::Assistant::ToolCall
  # @rbs context: Riffer::Agent::Context?
  # @rbs assistant_message: Riffer::Messages::Assistant?
  # @rbs &: () -> Riffer::Tools::Response
  # @rbs return: Riffer::Tools::Response
  def around_tool_call(tool_call, context:, assistant_message: nil)
    started = @clock.call
    @emit.call(Riffer::Rig::Events::ToolRunning.new(tool_call.call_id, tool_call.name, started))
    response = yield
    finished = @clock.call
    @emit.call(
      Riffer::Rig::Events::ToolDone.new(
        tool_call.call_id, tool_call.name, finished, finished - started, response.error?
      )
    )
    response
  end

  private

  # @rbs tool_call: Riffer::Messages::Assistant::ToolCall
  # @rbs tools: Array[singleton(Riffer::Tool)]
  # @rbs context: Riffer::Agent::Context?
  # @rbs assistant_message: Riffer::Messages::Assistant?
  # @rbs return: Riffer::Tools::Response
  def dispatch_tool_call(tool_call, tools:, context:, assistant_message: nil)
    args = parse_arguments(tool_call.arguments)
    return super unless args.is_a?(Hash)

    verdict = @hooks.before_tool_call(tool_call.name, args)
    return Riffer::Tools::Response.error(verdict.reason, type: :blocked) if verdict.is_a?(Riffer::Rig::Runtime::Blocked)

    call = verdict.equal?(args) ? tool_call : replace_arguments(tool_call, verdict)
    response = super(call, tools: tools, context: context, assistant_message: assistant_message)
    @hooks.observe(:after_tool_call, Riffer::Rig::Events::AfterToolCall.new(tool_call.name, verdict, response))
    response
  rescue JSON::ParserError
    super
  end

  # @rbs tool_call: Riffer::Messages::Assistant::ToolCall
  # @rbs args: Hash[Symbol, untyped]
  # @rbs return: Riffer::Messages::Assistant::ToolCall
  def replace_arguments(tool_call, args)
    Riffer::Messages::Assistant::ToolCall.new(call_id: tool_call.call_id, name: tool_call.name, arguments: args.to_json)
  end
end
