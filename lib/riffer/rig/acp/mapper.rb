# frozen_string_literal: true

module Riffer::Rig::ACP::Mapper
  extend self

  TOOL_KINDS = {
    'read' => ::ACP::Types::ToolKind::READ,
    'write' => ::ACP::Types::ToolKind::EDIT,
    'edit' => ::ACP::Types::ToolKind::EDIT,
    'bash' => ::ACP::Types::ToolKind::EXECUTE
  }.freeze #: Hash[String, String]

  # Text and resource links are ACP's must-support prompt blocks; the client
  # cannot send the others unless the agent advertised them.
  # @rbs blocks: Array[::ACP::Types::ContentBlock::t]
  # @rbs return: String
  def prompt_text(blocks)
    blocks.filter_map { |block| prompt_text_of(block) }.join("\n\n")
  end

  # @rbs content: String
  # @rbs return: ::ACP::Types::SessionUpdate::AgentMessageChunk
  def message_chunk(content)
    ::ACP::Types::SessionUpdate::AgentMessageChunk.new(content: text_block(content))
  end

  # @rbs message: Hash[Symbol, untyped]
  # @rbs return: ::ACP::Types::SessionUpdate::t?
  def replay_of(message)
    case message[:role]
    when 'user' then ::ACP::Types::SessionUpdate::UserMessageChunk.new(content: text_block(message[:content].to_s))
    when 'assistant' then message_chunk(message[:content].to_s)
    when 'tool' then replayed_tool_call(message)
    end
  end

  # @rbs event: Riffer::StreamEvents::ToolCallDone
  # @rbs return: ::ACP::Types::SessionUpdate::ToolCall
  def tool_call(event)
    ::ACP::Types::SessionUpdate::ToolCall.new(
      tool_call_id: event.call_id,
      title: "#{event.name}(#{event.arguments})",
      name: event.name,
      kind: TOOL_KINDS.fetch(event.name, ::ACP::Types::ToolKind::OTHER),
      status: ::ACP::Types::ToolCallStatus::IN_PROGRESS
    )
  end

  # @rbs event: Riffer::Rig::Events::AfterToolCall
  # @rbs return: ::ACP::Types::SessionUpdate::ToolCallUpdate
  def tool_call_done(event)
    result = event.result
    ::ACP::Types::SessionUpdate::ToolCallUpdate.new(
      tool_call_id: event.call_id,
      status: result.error? ? ::ACP::Types::ToolCallStatus::FAILED : ::ACP::Types::ToolCallStatus::COMPLETED,
      content: tool_content(result.content)
    )
  end

  # riffer's failure reasons (:error, :other, :guardrail_blocked) have no ACP
  # counterpart; refusal is the closest signal that the turn did not complete.
  # @rbs stop_reason: Symbol?
  # @rbs return: String
  def stop_reason_of(stop_reason)
    case stop_reason
    when :completed then ::ACP::Types::StopReason::END_TURN
    when Riffer::Rig::Runtime::INTERRUPT_CANCELLED then ::ACP::Types::StopReason::CANCELLED
    when :max_steps then ::ACP::Types::StopReason::MAX_TURN_REQUESTS
    else
      stopped = Riffer::Rig::Runtime::STOPPED_WITHOUT_COMPLETING.include?(stop_reason)
      stopped ? ::ACP::Types::StopReason::MAX_TOKENS : ::ACP::Types::StopReason::REFUSAL
    end
  end

  private

  # @rbs block: ::ACP::Types::ContentBlock::t
  # @rbs return: String?
  def prompt_text_of(block)
    case block
    when ::ACP::Types::ContentBlock::Text then block.text
    when ::ACP::Types::ContentBlock::ResourceLink then "#{block.title || block.name} #{block.uri}"
    end
  end

  # @rbs text: String
  # @rbs return: ::ACP::Types::ContentBlock::Text
  def text_block(text)
    ::ACP::Types::ContentBlock::Text.new(text: text)
  end

  # The stored result is all a replayed call has: the arguments live in the
  # assistant message's tool_calls, so the title is the name alone.
  # @rbs message: Hash[Symbol, untyped]
  # @rbs return: ::ACP::Types::SessionUpdate::ToolCall
  def replayed_tool_call(message)
    name = message[:name].to_s
    ::ACP::Types::SessionUpdate::ToolCall.new(
      tool_call_id: message[:tool_call_id].to_s,
      title: name,
      name: name,
      kind: TOOL_KINDS.fetch(name, ::ACP::Types::ToolKind::OTHER),
      status: ::ACP::Types::ToolCallStatus::COMPLETED,
      content: tool_content(message[:content].to_s)
    )
  end

  # @rbs text: String
  # @rbs return: Array[::ACP::Types::ToolCallContent::t]
  def tool_content(text)
    [::ACP::Types::ToolCallContent::Content.new(content: text_block(text))]
  end
end
