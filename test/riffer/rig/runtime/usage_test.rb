# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::Usage do
  def usage(input, output)
    Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output)
  end

  it 'sums the token usage of the assistant messages' do
    messages = [
      Riffer::Messages::User.new('hello'),
      Riffer::Messages::Assistant.new('Hi there.', token_usage: usage(10, 5)),
      Riffer::Messages::Assistant.new('Second.', token_usage: usage(20, 7))
    ]

    assert_equal usage(30, 12).to_h, Riffer::Rig::Runtime::Usage.sum(messages).to_h
  end

  it 'is nil when no message carries usage' do
    messages = [Riffer::Messages::User.new('hello'), Riffer::Messages::Assistant.new('No usage.')]

    assert_nil Riffer::Rig::Runtime::Usage.sum(messages)
  end

  it 'totals the usages, skipping a missing one' do
    assert_equal usage(30, 12).to_h, Riffer::Rig::Runtime::Usage.total([usage(10, 5), nil, usage(20, 7)]).to_h
  end

  it 'totals to nil when there is no usage' do
    assert_nil Riffer::Rig::Runtime::Usage.total([nil, nil])
  end
end
