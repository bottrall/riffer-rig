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

  def after_tool_call(response)
    Riffer::Rig::Events::AfterToolCall.new('call_1', 'read', { path: 'x' }, response, 4.5, 2.5)
  end

  it 'serializes a before_tool_call with the call it starts' do
    event = Riffer::Rig::Events::BeforeToolCall.new('call_1', 'read', { path: 'x' }, 2.0)

    assert_equal(
      { 'type' => 'before_tool_call', 'call_id' => 'call_1', 'tool' => 'read', 'args' => { 'path' => 'x' },
        'at' => 2.0 },
      JSON.parse(Riffer::Rig::Headless::Ndjson.line(event))
    )
  end

  it 'serializes an after_tool_call with its result and timing' do
    line = Riffer::Rig::Headless::Ndjson.line(after_tool_call(Riffer::Tools::Response.text('ok')))

    assert_equal(
      { 'type' => 'after_tool_call', 'call_id' => 'call_1', 'tool' => 'read', 'args' => { 'path' => 'x' },
        'result' => { 'content' => 'ok', 'error' => nil, 'error_type' => nil }, 'at' => 4.5, 'duration' => 2.5 },
      JSON.parse(line)
    )
  end

  it 'serializes an error result as its message and type, without the exception' do
    response = Riffer::Tools::Response.error('boom', type: :unhandled_error, exception: RuntimeError.new('boom'))
    line = Riffer::Rig::Headless::Ndjson.line(after_tool_call(response))

    assert_equal(
      { 'content' => 'boom', 'error' => 'boom', 'error_type' => 'unhandled_error' }, JSON.parse(line).fetch('result')
    )
  end

  it 'renders a fatal message as an error record' do
    line = Riffer::Rig::Headless::Ndjson.error('boom')

    assert_equal "{\"type\":\"error\",\"message\":\"boom\"}\n", line
  end
end
