# frozen_string_literal: true

module Riffer::Rig::ACP::Mapper
  extend self

  TOOL_KINDS = {
    'read' => ::ACP::Types::ToolKind::READ,
    'write' => ::ACP::Types::ToolKind::EDIT,
    'edit' => ::ACP::Types::ToolKind::EDIT,
    'bash' => ::ACP::Types::ToolKind::EXECUTE
  }.freeze #: Hash[String, String]

  CONFIRMED = 'yes' #: String
  CONFIRM_OPTIONS = [
    ::ACP::Types::PermissionOption.new(
      option_id: CONFIRMED, name: 'Yes', kind: ::ACP::Types::PermissionOptionKind::ALLOW_ONCE
    ),
    ::ACP::Types::PermissionOption.new(option_id: 'no', name: 'No', kind: ::ACP::Types::PermissionOptionKind::REJECT_ONCE)
  ].freeze #: Array[::ACP::Types::PermissionOption]
  ANSWER_FIELD = 'answer' #: String

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

  # @rbs return: ::ACP::Types::SessionUpdate::AgentMessageChunk
  def job_exit
    # ACP has no update for a job exit notice, and without a break the replies
    # either side of one read as a single message.
    message_chunk("\n\n")
  end

  # @rbs completion: Riffer::Rig::Runtime::JobCompletion
  # @rbs return: ::ACP::Types::SessionUpdate::AgentMessageChunk
  def job_completion(completion)
    message_chunk(
      "\n\nBackground job #{completion.job_id} exited with status #{completion.exit_status}: #{completion.command}\n\n"
    )
  end

  # @rbs message: Hash[Symbol, untyped]
  # @rbs return: ::ACP::Types::SessionUpdate::t?
  def replay_of(message)
    return job_exit if message[Riffer::Rig::Runtime::JobNotification::MARKER]

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

  # @rbs options: Array[String]
  # @rbs return: Array[::ACP::Types::PermissionOption]
  def choices(options)
    options.map do |option|
      ::ACP::Types::PermissionOption.new(
        option_id: option, name: option, kind: ::ACP::Types::PermissionOptionKind::ALLOW_ONCE
      )
    end
  end

  # @rbs tool_call_id: String
  # @rbs question: String
  # @rbs return: ::ACP::Types::SessionUpdate::ToolCall
  def permission_call(tool_call_id, question)
    ::ACP::Types::SessionUpdate::ToolCall.new(
      tool_call_id: tool_call_id,
      title: question,
      kind: ::ACP::Types::ToolKind::OTHER,
      status: ::ACP::Types::ToolCallStatus::PENDING
    )
  end

  # @rbs session_id: String
  # @rbs tool_call_id: String
  # @rbs question: String
  # @rbs options: Array[::ACP::Types::PermissionOption]
  # @rbs return: ::ACP::Types::RequestPermissionRequest
  def permission_request(session_id, tool_call_id, question, options)
    ::ACP::Types::RequestPermissionRequest.new(
      session_id: session_id,
      tool_call: ::ACP::Types::ToolCallUpdate.new(
        tool_call_id: tool_call_id,
        title: question,
        kind: ::ACP::Types::ToolKind::OTHER,
        status: ::ACP::Types::ToolCallStatus::PENDING
      ),
      options: options
    )
  end

  # @rbs response: ::ACP::Types::RequestPermissionResponse | ::ACP::RequestError
  # @rbs return: String?
  def selected_option(response)
    return nil unless response.is_a?(::ACP::Types::RequestPermissionResponse)

    outcome = response.outcome
    outcome.option_id if outcome.is_a?(::ACP::Types::RequestPermissionOutcome::Selected)
  end

  # @rbs tool_call_id: String
  # @rbs selected: String?
  # @rbs return: ::ACP::Types::SessionUpdate::ToolCallUpdate
  def permission_done(tool_call_id, selected)
    ::ACP::Types::SessionUpdate::ToolCallUpdate.new(
      tool_call_id: tool_call_id,
      status: selected ? ::ACP::Types::ToolCallStatus::COMPLETED : ::ACP::Types::ToolCallStatus::FAILED
    )
  end

  # @rbs session_id: String
  # @rbs question: String
  # @rbs return: ::ACP::Types::CreateElicitationRequest
  def elicitation_request(session_id, question)
    ::ACP::Types::CreateElicitationRequest.new(
      message: question,
      mode: ::ACP::Types::CreateElicitationRequest::Mode::Form.new(
        requested_schema: ::ACP::Types::ElicitationSchema.new(
          type: ::ACP::Types::ElicitationSchemaType::OBJECT,
          properties: {
            ANSWER_FIELD => ::ACP::Types::ElicitationPropertySchema::StringPropertySchema.new(title: question)
          },
          required: [ANSWER_FIELD]
        ),
        scope: ::ACP::Types::ElicitationSessionScope.new(session_id: session_id)
      )
    )
  end

  # @rbs response: ::ACP::Types::CreateElicitationResponse | ::ACP::RequestError
  # @rbs return: String?
  def elicited_answer(response)
    return nil unless response.is_a?(::ACP::Types::CreateElicitationResponse)

    action = response.action
    return nil unless action.is_a?(::ACP::Types::CreateElicitationResponse::Action::Accept)

    answer = action.content&.fetch(ANSWER_FIELD, nil)
    answer if answer.is_a?(String)
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
