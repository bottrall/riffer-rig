# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::Snapshot do
  before do
    @host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
  end

  def usage(input, output)
    Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output)
  end

  def conversation
    [Riffer::Messages::User.new('hello'), Riffer::Messages::Assistant.new('Hi there.', token_usage: usage(10, 5))]
  end

  def snapshot(messages: conversation, model: nil, skills: [])
    Riffer::Rig::Runtime::Snapshot.new(id: 'session-1', messages: messages, model: model, skills: skills)
  end

  def orphaned_call
    call = Riffer::Messages::Assistant::ToolCall.new(call_id: 'orphan', name: 'read', arguments: '{"path":"/tmp/x"}')
    Riffer::Messages::Assistant.new('', tool_calls: [call])
  end

  describe '.from_h' do
    it 'raises on a hash that is not a snapshot' do
      assert_raises(KeyError) { Riffer::Rig::Runtime::Snapshot.from_h({ id: 'session-1' }) }
    end

    it 'reads back what to_h wrote' do
      saved = snapshot(model: 'mock/other', skills: %w[a]).to_h

      assert_equal saved, Riffer::Rig::Runtime::Snapshot.from_h(saved).to_h
    end

    it 'reads the messages back from a JSON round trip' do
      saved = JSON.parse(JSON.generate(snapshot.to_h), symbolize_names: true)

      assert_equal ['hello', 'Hi there.'], Riffer::Rig::Runtime::Snapshot.from_h(saved).messages.map(&:content)
    end
  end

  describe '#to_h' do
    it 'holds the id, the messages as riffer hashes, the model and the skills' do
      messages = conversation
      expected = { id: 'session-1', messages: messages.map(&:to_h), model: 'mock/other', skills: %w[a] }

      assert_equal expected, snapshot(messages: messages, model: 'mock/other', skills: %w[a]).to_h
    end
  end

  describe '#session' do
    it 'carries the messages' do
      messages = conversation

      assert_equal messages, snapshot(messages: messages).session.messages
    end

    it 'heals an orphaned tail tool call with an interrupted result' do
      healed = snapshot(messages: [*conversation, orphaned_call]).session.messages.last

      assert_equal ['orphan', :interrupted], [healed.tool_call_id, healed.error_type]
    end

    it 'leaves its own messages unhealed' do
      orphaned = snapshot(messages: [*conversation, orphaned_call])
      orphaned.session

      assert_equal 3, orphaned.messages.length
    end
  end

  describe '#usage' do
    it 'sums the token usage of the messages' do
      messages = [*conversation, Riffer::Messages::Assistant.new('Second.', token_usage: usage(20, 7))]

      assert_equal usage(30, 12).to_h, snapshot(messages: messages).usage.to_h
    end
  end

  describe '#restorable_model' do
    it 'is nil when there is no saved model' do
      assert_nil snapshot.restorable_model({ mock: {} }, @host, 'mock/test')
    end

    it 'does not notify when there is no saved model' do
      snapshot.restorable_model({}, @host, 'mock/test')

      assert_empty @host.drain
    end

    it 'is the saved model when its provider has credentials' do
      assert_equal 'mock/other', snapshot(model: 'mock/other').restorable_model({ mock: {} }, @host, 'mock/test')
    end

    it 'does not notify when the saved model is restorable' do
      snapshot(model: 'mock/other').restorable_model({ mock: {} }, @host, 'mock/test')

      assert_empty @host.drain
    end

    it 'is nil when the saved provider has no credentials' do
      assert_nil snapshot(model: 'mock/other').restorable_model({}, @host, 'mock/test')
    end

    it 'notifies once when the saved provider has no credentials' do
      snapshot(model: 'mock/other').restorable_model({}, @host, 'mock/test')
      notice = 'Not restoring model mock/other: mock has no credentials; using mock/test'

      assert_equal [Riffer::Rig::Events::Notify.new(notice, :warning)], @host.drain
    end
  end
end
