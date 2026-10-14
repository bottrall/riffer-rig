# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Commands::Trace::Replay do
  def entry(message, second = nil)
    Riffer::Rig::Stores::MessageEntry.new(message: message.to_h, recorded_at: second && "2026-10-11T02:00:#{second}Z")
  end

  def user(content)
    Riffer::Messages::User.new(content)
  end

  def notification
    Riffer::Rig::Runtime::JobNotification.new(%(<background-job id="a1b2c3d4">\n<command>make</command>))
  end

  def assistant(content, *paths)
    calls = paths.map do |path|
      Riffer::Messages::Assistant::ToolCall.new(call_id: path, name: 'read', arguments: %({"path":"#{path}"}))
    end
    Riffer::Messages::Assistant.new(content, tool_calls: calls)
  end

  def result(path, **error)
    Riffer::Messages::Tool.new('content', tool_call_id: path, name: 'read', **error)
  end

  def multi_tool_turn
    [
      entry(user('Earlier prompt'), '00.000'),
      entry(assistant('Earlier answer.'), '00.500'),
      Riffer::Rig::Stores::ModelEntry.new(model: 'mock/other', recorded_at: '2026-10-11T02:00:00.900Z'),
      entry(user("Fix the failing test\nplease"), '01.000'),
      entry(assistant("I'll read both files.", 'a.rb', 'b.rb'), '02.250'),
      entry(result('a.rb'), '09.050'),
      entry(result('b.rb', error: 'No such file', error_type: :execution_error), '09.051'),
      entry(assistant('Fixed.'), '10.500')
    ]
  end

  def lines(entries)
    Riffer::Rig::Commands::Trace::Replay.lines(entries)
  end

  it 'replays the last turn in recorded order' do
    replay = [
      '02:00:01.000  prompt    Fix the failing test',
      "02:00:02.250  preamble  I'll read both files.",
      '02:00:02.250  dispatch  read {"path":"a.rb"}',
      '02:00:02.250  dispatch  read {"path":"b.rb"}',
      '              silent    6.8s',
      '02:00:09.050  finish    read',
      '02:00:09.051  finish    read (execution_error)',
      '02:00:10.500  answer    Fixed.'
    ]

    assert_equal replay, lines(multi_tool_turn)
  end

  it 'replays nothing without a user message' do
    assert_empty lines([entry(assistant('Hello.'), '00.000')])
  end

  it 'starts the turn at its prompt rather than at a job notification' do
    turn = [entry(user('Go'), '00.000'), entry(assistant('Started.'), '01.000'), entry(notification, '02.000')]

    assert_equal '02:00:00.000  prompt    Go', lines(turn).first
  end

  it 'marks a gap that reaches the threshold as silent' do
    turn = [entry(user('Go'), '00.000'), entry(assistant('Done.'), '05.000')]

    assert_equal '              silent    5.0s', lines(turn)[1]
  end

  it 'leaves a gap under the threshold unmarked' do
    turn = [entry(user('Go'), '00.000'), entry(assistant('Done.'), '04.999')]

    assert_equal 2, lines(turn).length
  end

  it 'marks no gap next to an unstamped entry' do
    turn = [entry(user('Go'), '00.000'), entry(assistant('Thinking.', 'a.rb')), entry(result('a.rb'), '30.000')]

    assert_empty lines(turn).grep(/silent/)
  end

  it 'replays a job notification as a notice' do
    turn = [entry(user('Go'), '00.000'), entry(assistant('Started.'), '01.000'), entry(notification, '02.000')]

    assert_equal '02:00:02.000  notice    <background-job id="a1b2c3d4">', lines(turn).last
  end

  it 'omits the prose line of a request that only called tools' do
    turn = [entry(user('Go'), '00.000'), entry(assistant('', 'a.rb'), '01.000')]

    assert_equal ['02:00:00.000  prompt    Go', '02:00:01.000  dispatch  read {"path":"a.rb"}'], lines(turn)
  end

  it 'leaves the time of an unstamped entry blank' do
    assert_equal ['              prompt    Go'], lines([entry(user('Go'))])
  end

  it 'strips control characters from the replayed text' do
    assert_equal ['              prompt    Go[2J'], lines([entry(user("Go\e[2J\a"))])
  end

  it 'shows the first line of the prose' do
    turn = [entry(user('Go'), '00.000'), entry(assistant("\n\nFirst.\nSecond."), '01.000')]

    assert_equal '02:00:01.000  answer    First.', lines(turn).last
  end
end
