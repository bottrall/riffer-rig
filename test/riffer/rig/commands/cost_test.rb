# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Commands::Cost do
  def usage(input, output, **rest)
    Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output, **rest)
  end

  def user(content)
    Riffer::Messages::User.new(content)
  end

  def assistant(content, token_usage = nil, tool_calls: [])
    Riffer::Messages::Assistant.new(content, tool_calls: tool_calls, token_usage: token_usage)
  end

  def job_notification
    Riffer::Rig::Runtime::JobNotification.new('<background-job id="a1b2c3d4">')
  end

  def two_turn_session
    call = Riffer::Messages::Assistant::ToolCall.new(call_id: 'c1', name: 'bash', arguments: '{"command":"bin/test"}')
    [
      Riffer::Messages::System.new('You are riffer.'),
      user('Fix it'),
      assistant('Running the tests.', usage(1200, 80, cache_write_tokens: 900, cost: 0.0051), tool_calls: [call]),
      Riffer::Messages::Tool.new('ok', tool_call_id: 'c1', name: 'bash'),
      assistant('All green.', usage(1400, 40, cache_read_tokens: 900, cost: 0.0012)),
      user('Thanks'),
      assistant('Welcome.', usage(1500, 12, cost: 0.0046))
    ]
  end

  def run_cost(messages)
    snapshot = { id: 'session-1', messages: messages.map(&:to_h), model: nil, skills: [] }
    events = []
    ctx = Riffer::Rig::Command::Context.new(
      'cost',
      '',
      runtime: Riffer::Rig::Runtime.new('mock/test', snapshot: snapshot),
      host: Riffer::Rig::Hosts::Null.new,
      settings: {},
      emit: ->(event) { events << event },
      turn: ->(_text) {}
    )
    Riffer::Rig::Commands::Cost.run(ctx)
    events
  end

  def lines(messages)
    run_cost(messages).first.text.lines(chomp: true)
  end

  it 'names the command cost' do
    assert_equal 'cost', Riffer::Rig::Commands::Cost.command.name
  end

  it 'says so when the session has no usage' do
    events = run_cost([user('Fix it'), assistant('Done.')])

    assert_equal [Riffer::Rig::Events::CommandOutput.new('cost', 'No usage recorded yet')], events
  end

  it 'says the session total and the usage of each turn' do
    breakdown = <<~TEXT.chomp
      session   ↑4100 · ↓132 · cache_write:900 · cache_read:900 · ~$0.0109
      turn 1    ↑2600 · ↓120 · cache_write:900 · cache_read:900 · ~$0.0063
      turn 2    ↑1500 · ↓12 · ~$0.0046
    TEXT

    assert_equal [Riffer::Rig::Events::CommandOutput.new('cost', breakdown)], run_cost(two_turn_session)
  end

  it 'counts no turn before the first user message' do
    session = [assistant('Earlier.', usage(5, 5)), user('Go'), assistant('Done.', usage(10, 5))]

    assert_equal ['session   ↑15 · ↓10', 'turn 1    ↑10 · ↓5'], lines(session)
  end

  it 'counts a turn continued by a job notification as one turn' do
    session = [user('Go'), assistant('Started.', usage(10, 5)), job_notification, assistant('Passed.', usage(20, 7))]

    assert_equal ['session   ↑30 · ↓12', 'turn 1    ↑30 · ↓12'], lines(session)
  end

  it 'starts no turn at a job notification ahead of a prompt' do
    session = [
      user('Go'),
      assistant('Started.', usage(10, 5)),
      job_notification,
      user('Again'),
      assistant('Passed.', usage(20, 7))
    ]

    assert_equal ['session   ↑30 · ↓12', 'turn 1    ↑10 · ↓5', 'turn 2    ↑20 · ↓7'], lines(session)
  end

  it 'marks a turn that reported no usage' do
    session = [user('Go'), assistant('Done.', usage(10, 5)), user('Again'), assistant('Stopped.')]

    assert_equal 'turn 2    no usage', lines(session).last
  end

  it 'omits a cache count of zero' do
    session = [user('Go'), assistant('Done.', usage(10, 5, cache_write_tokens: 0, cache_read_tokens: 0))]

    assert_equal 'turn 1    ↑10 · ↓5', lines(session).last
  end
end
