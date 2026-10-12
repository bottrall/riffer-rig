# frozen_string_literal: true

require 'json'

class Riffer::Rig::Runtime::ParallelToolRuntime < Riffer::Tools::Runtime
  # @rbs @hooks: Riffer::Rig::Runtime::Hooks

  # @rbs hooks: Riffer::Rig::Runtime::Hooks
  # @rbs runner: Riffer::Runner
  # @rbs return: void
  def initialize(hooks, runner)
    super(runner: runner)
    @hooks = hooks
  end

  # @rbs tool_calls: Array[Riffer::Messages::Assistant::ToolCall]
  # @rbs tools: Array[singleton(Riffer::Tool)]
  # @rbs context: Riffer::Agent::Context?
  # @rbs assistant_message: Riffer::Messages::Assistant?
  # @rbs tags: Hash[String, String]
  # @rbs return: Array[[Riffer::Messages::Assistant::ToolCall, Riffer::Tools::Response]]
  def execute(tool_calls, tools:, context:, assistant_message: nil, tags: {})
    verdicts = tool_calls.map { |tool_call| verdict(tool_call) }
    approved = verdicts.each_index.reject { |index| verdicts.fetch(index).is_a?(Riffer::Rig::Runtime::Blocked) }
    calls = approved.map { |index| approved_call(tool_calls.fetch(index), verdicts.fetch(index)) }
    # Only this call reaches the runner's workers: the hooks on either side of
    # it stay on the calling thread, so none has to be thread-safe.
    ran = super(calls, tools: tools, context: context, assistant_message: assistant_message, tags: tags)
    responses = approved.each_with_index.to_h { |index, slot| [index, ran.fetch(slot).last] }

    tool_calls.each_with_index.map do |tool_call, index|
      verdict = verdicts.fetch(index)
      if verdict.is_a?(Riffer::Rig::Runtime::Blocked)
        next instrument_tool_call(tool_call, tags) { Riffer::Tools::Response.error(verdict.reason, type: :blocked) }
      end

      response = responses.fetch(index)
      if verdict
        @hooks.observe(:after_tool_call, Riffer::Rig::Events::AfterToolCall.new(tool_call.name, verdict, response))
      end
      [tool_call, response]
    end
  end

  private

  # @rbs tool_call: Riffer::Messages::Assistant::ToolCall
  # @rbs return: Hash[Symbol, untyped] | Riffer::Rig::Runtime::Blocked | nil
  def verdict(tool_call)
    args = parse_arguments(tool_call.arguments)
    @hooks.before_tool_call(tool_call.name, args) if args.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  # @rbs tool_call: Riffer::Messages::Assistant::ToolCall
  # @rbs verdict: Hash[Symbol, untyped] | Riffer::Rig::Runtime::Blocked | nil
  # @rbs return: Riffer::Messages::Assistant::ToolCall
  def approved_call(tool_call, verdict)
    return tool_call unless verdict.is_a?(Hash)

    Riffer::Messages::Assistant::ToolCall.new(
      call_id: tool_call.call_id, name: tool_call.name, arguments: verdict.to_json
    )
  end
end
