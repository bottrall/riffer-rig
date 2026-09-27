# frozen_string_literal: true

require 'json'

class Riffer::Rig::Runtime::ToolRuntime < Riffer::Tools::Runtime
  # @rbs @hooks: Riffer::Rig::Runtime::Hooks

  # @rbs hooks: Riffer::Rig::Runtime::Hooks
  # @rbs return: void
  def initialize(hooks)
    # Sequential, so hooks never run concurrently.
    super(runner: Riffer::Runner::Sequential.new)
    @hooks = hooks
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
