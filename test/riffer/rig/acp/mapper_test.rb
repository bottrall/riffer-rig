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

  describe '.replay_of' do
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

    it 'maps the built-in tools to their ACP kinds' do
      kinds = %w[read write edit bash].to_h do |name|
        [name, Riffer::Rig::ACP::Mapper.tool_call(tool_call_done(name)).kind]
      end

      assert_equal({ 'read' => 'read', 'write' => 'edit', 'edit' => 'edit', 'bash' => 'execute' }, kinds)
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
      reasons = %i[context_window length content_filter malformed_output]

      assert_equal %w[max_tokens], reasons.map { |reason| Riffer::Rig::ACP::Mapper.stop_reason_of(reason) }.uniq
    end

    it 'ends a failed turn with refusal' do
      reasons = [:error, :other, :guardrail_blocked, nil]

      assert_equal %w[refusal], reasons.map { |reason| Riffer::Rig::ACP::Mapper.stop_reason_of(reason) }.uniq
    end
  end
end
