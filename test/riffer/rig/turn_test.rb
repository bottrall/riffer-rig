# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Turn do
  def response(outcome:, messages: [], token_usage: nil)
    Riffer::Agent::Response.new('', outcome: outcome, messages: messages, token_usage: token_usage)
  end

  def tool_call
    Riffer::Messages::Assistant::ToolCall.new(call_id: 'call_1', name: 'read', arguments: '{"path":"x"}')
  end

  def message_with_tool_calls(call)
    Riffer::Messages::Assistant.new('', tool_calls: [call])
  end

  def response_with_messages(message)
    response(outcome: Riffer::Agent::Outcome.new(reason: :completed), messages: [message])
  end

  describe '.from_response' do
    it 'maps the completed outcome to the stop reason' do
      turn = Riffer::Rig::Turn.from_response(response(outcome: Riffer::Agent::Outcome.new(reason: :completed)))

      assert_equal :stop, turn.stop_reason
    end

    it 'passes a provider finish-reason outcome through as the stop reason' do
      turn = Riffer::Rig::Turn.from_response(response(outcome: Riffer::Agent::Outcome.new(reason: :length)))

      assert_equal :length, turn.stop_reason
    end

    it 'collects the tool call ids' do
      call = tool_call
      turn = Riffer::Rig::Turn.from_response(response_with_messages(message_with_tool_calls(call)))

      assert_equal ['call_1'], turn.tool_calls.map(&:id)
    end

    it 'collects the tool call names' do
      call = tool_call
      turn = Riffer::Rig::Turn.from_response(response_with_messages(message_with_tool_calls(call)))

      assert_equal ['read'], turn.tool_calls.map(&:name)
    end

    it 'collects the tool call arguments' do
      call = tool_call
      turn = Riffer::Rig::Turn.from_response(response_with_messages(message_with_tool_calls(call)))

      assert_equal ['{"path":"x"}'], turn.tool_calls.map(&:arguments)
    end

    it 'carries the run token usage' do
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5, cost: 0.01)
      turn = Riffer::Rig::Turn.from_response(
        response(outcome: Riffer::Agent::Outcome.new(reason: :completed), token_usage: usage)
      )

      assert_equal usage, turn.usage
    end
  end

  describe '#cost' do
    it 'is the usage cost when usage carries one' do
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5, cost: 0.01)
      turn = Riffer::Rig::Turn.new(usage: usage)

      assert_in_delta 0.01, turn.cost
    end

    it 'is nil without usage or priced tokens' do
      assert_nil Riffer::Rig::Turn.new.cost
    end
  end

  it 'is frozen' do
    turn = Riffer::Rig::Turn.new

    assert_predicate turn, :frozen?
  end
end
