# frozen_string_literal: true

require 'test_helper'
require 'json'

describe Riffer::Rig::Headless::Ndjson do
  it 'serializes a riffer stream event as a flat envelope' do
    line = Riffer::Rig::Headless::Ndjson.line(Riffer::StreamEvents::TextDelta.new('Re'))

    assert_equal "{\"role\":\"assistant\",\"content\":\"Re\",\"type\":\"text_delta\"}\n", line
  end

  it 'snake_cases the multi-word stream event classes' do
    line = Riffer::Rig::Headless::Ndjson.line(Riffer::StreamEvents::TokenUsageDone.new(token_usage: nil))

    assert_equal 'token_usage_done', JSON.parse(line).fetch('type')
  end

  it 'serializes a rig event with its type and fields' do
    line = Riffer::Rig::Headless::Ndjson.line(Riffer::Rig::Events::SessionStart.new('abc', :new))

    assert_equal({ 'type' => 'session_start', 'id' => 'abc', 'reason' => 'new' }, JSON.parse(line))
  end

  it 'serializes a nested riffer object through its to_h' do
    message = Riffer::Messages::Assistant.new(
      'Hi',
      token_usage: Riffer::Providers::TokenUsage.new(
        input_tokens: 10, output_tokens: 5, cache_write_tokens: 0, cache_read_tokens: 0, cost: nil
      )
    )
    line = Riffer::Rig::Headless::Ndjson.line(Riffer::Rig::Events::AfterResponse.new(message))

    assert_equal 10, JSON.parse(line).dig('message', 'token_usage', 'input_tokens')
  end

  it 'serializes a tool response through its to_h' do
    response = Riffer::Tools::Response.new(content: 'ok', success: true)
    line = Riffer::Rig::Headless::Ndjson.line(Riffer::Rig::Events::AfterToolCall.new('read', { path: 'x' }, response))

    assert_equal({ 'content' => 'ok', 'error' => nil, 'error_type' => nil }, JSON.parse(line).fetch('result'))
  end

  it 'renders a fatal message as an error record' do
    line = Riffer::Rig::Headless::Ndjson.error('boom')

    assert_equal "{\"type\":\"error\",\"message\":\"boom\"}\n", line
  end
end
