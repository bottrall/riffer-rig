# frozen_string_literal: true

require 'test_helper'
require 'acp/sdk'

describe Riffer::Rig::ACP::Mapper do
  def text(content)
    ACP::Types::ContentBlock::Text.new(text: content)
  end

  def tool_call_done(name)
    Riffer::StreamEvents::ToolCallDone.new(item_id: 'i1', call_id: 'c1', name: name, arguments: '{"path":"x"}')
  end

  def after_tool_call(result)
    Riffer::Rig::Events::AfterToolCall.new('c1', 'read', { path: 'x' }, result, 4.5, 2.5)
  end

  def tool_message(name)
    { role: 'tool', tool_call_id: 'c1', name: name, content: 'contents' }
  end

  describe '.prompt_text' do
    it 'joins the text blocks with a blank line' do
      assert_equal "one\n\ntwo", Riffer::Rig::ACP::Mapper.prompt_text([text('one'), text('two')])
    end

    it 'renders a resource link as its title and uri' do
      link = ACP::Types::ContentBlock::ResourceLink.new(name: 'notes.md', uri: 'file:///notes.md', title: 'Notes')

      assert_equal 'Notes file:///notes.md', Riffer::Rig::ACP::Mapper.prompt_text([link])
    end

    it 'falls back to the name of an untitled resource link' do
      link = ACP::Types::ContentBlock::ResourceLink.new(name: 'notes.md', uri: 'file:///notes.md')

      assert_equal 'notes.md file:///notes.md', Riffer::Rig::ACP::Mapper.prompt_text([link])
    end

    it 'drops the blocks the agent did not advertise' do
      image = ACP::Types::ContentBlock::Image.new(data: 'AAAA', mime_type: 'image/png')

      assert_equal 'one', Riffer::Rig::ACP::Mapper.prompt_text([text('one'), image])
    end
  end

  describe '.message_chunk' do
    it 'wraps the content in an agent message chunk' do
      assert_equal 'Hi', Riffer::Rig::ACP::Mapper.message_chunk('Hi').content.text
    end
  end

  describe '.job_exit' do
    it 'is an agent message chunk holding a blank line' do
      update = Riffer::Rig::ACP::Mapper.job_exit

      assert_equal [ACP::Types::SessionUpdate::AgentMessageChunk, "\n\n"], [update.class, update.content.text]
    end
  end

  describe '.job_completion' do
    it 'is an agent message chunk naming the job, its exit status and its command in a paragraph of its own' do
      completion = Riffer::Rig::Runtime::JobCompletion.new(
        job_id: 'a1b2c3d4', command: 'make test', exit_status: 2, duration: 1.5, output_path: '/tmp/job.log', tail: ''
      )
      update = Riffer::Rig::ACP::Mapper.job_completion(completion)
      text = "\n\nBackground job a1b2c3d4 exited with status 2: make test\n\n"

      assert_equal [ACP::Types::SessionUpdate::AgentMessageChunk, text], [update.class, update.content.text]
    end
  end

  describe '.replay_of' do
    it 'replays a job notification as a paragraph break rather than as typed input' do
      stored = { role: 'user', content: '<background-job id="a1b2c3d4">', job_notification: true }

      assert_equal Riffer::Rig::ACP::Mapper.job_exit.to_h, Riffer::Rig::ACP::Mapper.replay_of(stored).to_h
    end

    it 'replays a user message as a user message chunk' do
      update = Riffer::Rig::ACP::Mapper.replay_of({ role: 'user', content: 'hello' })

      assert_equal [ACP::Types::SessionUpdate::UserMessageChunk, 'hello'], [update.class, update.content.text]
    end

    it 'replays an assistant message as an agent message chunk' do
      update = Riffer::Rig::ACP::Mapper.replay_of({ role: 'assistant', content: 'Reading.' })

      assert_equal [ACP::Types::SessionUpdate::AgentMessageChunk, 'Reading.'], [update.class, update.content.text]
    end

    it 'replays a tool message as a completed tool call titled with its name' do
      update = Riffer::Rig::ACP::Mapper.replay_of(tool_message('read'))

      assert_equal %w[c1 read read completed], [update.tool_call_id, update.title, update.name, update.status]
    end

    it 'maps a replayed built-in tool to its ACP kind' do
      assert_equal 'execute', Riffer::Rig::ACP::Mapper.replay_of(tool_message('bash')).kind
    end

    it 'maps any other replayed tool to the other kind' do
      assert_equal 'other', Riffer::Rig::ACP::Mapper.replay_of(tool_message('mcp__stub__ping')).kind
    end

    it 'attaches the stored result to a replayed tool call' do
      update = Riffer::Rig::ACP::Mapper.replay_of(tool_message('read'))

      assert_equal(['contents'], update.content.map { |item| item.content.text })
    end

    it 'skips a message of any other role' do
      assert_nil Riffer::Rig::ACP::Mapper.replay_of({ role: 'system', content: 'Be brief.' })
    end
  end

  describe '.tool_call' do
    it 'reports an in-progress call titled with its arguments' do
      update = Riffer::Rig::ACP::Mapper.tool_call(tool_call_done('read'))

      assert_equal(
        ['c1', 'read({"path":"x"})', 'read', 'in_progress'],
        [update.tool_call_id, update.title, update.name, update.status]
      )
    end

    it 'maps a built-in tool to its ACP kind' do
      assert_equal 'execute', Riffer::Rig::ACP::Mapper.tool_call(tool_call_done('bash')).kind
    end

    it 'maps any other tool to the other kind' do
      assert_equal 'other', Riffer::Rig::ACP::Mapper.tool_call(tool_call_done('mcp__stub__ping')).kind
    end
  end

  describe '.tool_call_done' do
    it 'completes a call that succeeded' do
      update = Riffer::Rig::ACP::Mapper.tool_call_done(after_tool_call(Riffer::Tools::Response.text('ok')))

      assert_equal %w[c1 completed], [update.tool_call_id, update.status]
    end

    it 'fails a call that returned an error' do
      update = Riffer::Rig::ACP::Mapper.tool_call_done(after_tool_call(Riffer::Tools::Response.error('boom')))

      assert_equal 'failed', update.status
    end

    it 'attaches the result to the update' do
      update = Riffer::Rig::ACP::Mapper.tool_call_done(after_tool_call(Riffer::Tools::Response.text('ok')))

      assert_equal(['ok'], update.content.map { |item| item.content.text })
    end
  end

  describe '.stop_reason_of' do
    it 'ends a completed turn with end_turn' do
      assert_equal 'end_turn', Riffer::Rig::ACP::Mapper.stop_reason_of(:completed)
    end

    it 'ends a cancelled turn with cancelled' do
      assert_equal 'cancelled', Riffer::Rig::ACP::Mapper.stop_reason_of(Riffer::Rig::Runtime::INTERRUPT_CANCELLED)
    end

    it 'ends a turn that hit the step cap with max_turn_requests' do
      assert_equal 'max_turn_requests', Riffer::Rig::ACP::Mapper.stop_reason_of(:max_steps)
    end

    it 'ends a turn the provider stopped early with max_tokens' do
      assert_equal 'max_tokens', Riffer::Rig::ACP::Mapper.stop_reason_of(:length)
    end

    it 'ends a failed turn with refusal' do
      reasons = [:error, :other, :guardrail_blocked, nil]

      assert_equal %w[refusal], reasons.map { |reason| Riffer::Rig::ACP::Mapper.stop_reason_of(reason) }.uniq
    end
  end

  describe '.choices' do
    it 'offers each option under its own text as the id' do
      assert_equal(%w[red blue], Riffer::Rig::ACP::Mapper.choices(%w[red blue]).map(&:option_id))
    end
  end

  describe '.permission_call' do
    it 'announces a pending tool call titled with the question' do
      call = Riffer::Rig::ACP::Mapper.permission_call('c1', 'Proceed?')

      assert_equal %w[c1 Proceed? other pending], [call.tool_call_id, call.title, call.kind, call.status]
    end
  end

  describe '.permission_request' do
    def request
      Riffer::Rig::ACP::Mapper.permission_request('s1', 'c1', 'Proceed?', Riffer::Rig::ACP::Mapper::CONFIRM_OPTIONS)
    end

    it 'names the session' do
      assert_equal 's1', request.session_id
    end

    it 'carries the question as the title of a pending tool call' do
      call = request.tool_call

      assert_equal %w[c1 Proceed? pending], [call.tool_call_id, call.title, call.status]
    end

    it 'offers the options it was given' do
      assert_equal Riffer::Rig::ACP::Mapper::CONFIRM_OPTIONS, request.options
    end
  end

  describe '.selected_option' do
    it 'reads nothing from a request error' do
      assert_nil Riffer::Rig::ACP::Mapper.selected_option(ACP::RequestError.resource_not_found)
    end

    it 'reads nothing from a cancelled outcome' do
      response = ACP::Types::RequestPermissionResponse.new(outcome: ACP::Types::RequestPermissionOutcome::Cancelled.new)

      assert_nil Riffer::Rig::ACP::Mapper.selected_option(response)
    end

    it 'reads the option id of a selected outcome' do
      response = ACP::Types::RequestPermissionResponse.new(
        outcome: ACP::Types::RequestPermissionOutcome::Selected.new(option_id: 'yes')
      )

      assert_equal 'yes', Riffer::Rig::ACP::Mapper.selected_option(response)
    end
  end

  describe '.permission_done' do
    it 'completes the tool call of a question the client answered, no included' do
      update = Riffer::Rig::ACP::Mapper.permission_done('c1', 'no')

      assert_equal %w[c1 completed], [update.tool_call_id, update.status]
    end

    it 'fails the tool call of a question the client left unanswered' do
      assert_equal 'failed', Riffer::Rig::ACP::Mapper.permission_done('c1', nil).status
    end
  end

  describe '.elicitation_request' do
    def request
      Riffer::Rig::ACP::Mapper.elicitation_request('s1', 'Name?')
    end

    it 'carries the question as its message' do
      assert_equal 'Name?', request.message
    end

    it 'scopes a form to the session' do
      assert_equal 's1', request.mode.scope.session_id
    end

    it 'asks for a string answer titled with the question' do
      answer = request.mode.requested_schema.properties.fetch('answer')

      assert_equal [ACP::Types::ElicitationPropertySchema::StringPropertySchema, 'Name?'], [answer.class, answer.title]
    end

    it 'requires the answer' do
      assert_equal ['answer'], request.mode.requested_schema.required
    end
  end

  describe '.elicited_answer' do
    def accepted(content)
      ACP::Types::CreateElicitationResponse.new(
        action: ACP::Types::CreateElicitationResponse::Action::Accept.new(content: content)
      )
    end

    it 'reads nothing from a request error' do
      assert_nil Riffer::Rig::ACP::Mapper.elicited_answer(ACP::RequestError.resource_not_found)
    end

    it 'reads nothing from a cancelled form' do
      response = ACP::Types::CreateElicitationResponse.new(
        action: ACP::Types::CreateElicitationResponse::Action::Cancel.new
      )

      assert_nil Riffer::Rig::ACP::Mapper.elicited_answer(response)
    end

    it 'reads nothing from an accepted form without content' do
      assert_nil Riffer::Rig::ACP::Mapper.elicited_answer(accepted(nil))
    end

    it 'reads nothing from an answer that is not a string' do
      assert_nil Riffer::Rig::ACP::Mapper.elicited_answer(accepted('answer' => 3))
    end

    it 'reads the answer field of an accepted form' do
      assert_equal 'Ada', Riffer::Rig::ACP::Mapper.elicited_answer(accepted('answer' => 'Ada'))
    end
  end
end
