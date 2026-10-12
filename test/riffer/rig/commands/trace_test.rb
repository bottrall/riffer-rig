# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Commands::Trace do
  before do
    @home = Dir.mktmpdir
    @store = Riffer::Rig::Stores::JSONL.new(home: @home)
    @runtime = Riffer::Rig::Runtime.new('mock/test')
  end

  after do
    FileUtils.remove_entry(@home)
  end

  def header
    Riffer::Rig::Stores::Header.new(
      schema_version: 1,
      id: @runtime.id,
      cwd: '/project',
      created_at: '2026-10-11T02:00:00Z',
      model: 'mock/test',
      riffer_rig_version: '0.9.0',
      riffer_version: '0.51.0',
      title: 'Fix it'
    )
  end

  def record(message, recorded_at)
    @store.append(@runtime.id, Riffer::Rig::Stores::MessageEntry.new(message: message.to_h, recorded_at: recorded_at))
  end

  def record_turn
    @store.append(@runtime.id, header)
    call = Riffer::Messages::Assistant::ToolCall.new(call_id: 'c1', name: 'bash', arguments: '{"command":"bin/test"}')
    record(Riffer::Messages::User.new('Fix it'), '2026-10-11T02:00:00.000Z')
    record(Riffer::Messages::Assistant.new('Running the tests.', tool_calls: [call]), '2026-10-11T02:00:01.000Z')
    record(Riffer::Messages::Tool.new('ok', tool_call_id: 'c1', name: 'bash'), '2026-10-11T02:00:02.000Z')
    record(Riffer::Messages::Assistant.new('All green.'), '2026-10-11T02:00:03.000Z')
  end

  def run_trace
    events = []
    ctx = Riffer::Rig::Command::Context.new(
      'trace',
      '',
      runtime: @runtime,
      host: Riffer::Rig::Hosts::Null.new,
      settings: {},
      emit: ->(event) { events << event },
      turn: ->(_text) {}
    )
    Riffer::Rig::Commands::Trace.run(@store, ctx)
    events
  end

  it 'names the command trace' do
    assert_equal 'trace', Riffer::Rig::Commands::Trace.command(@store).name
  end

  it 'says the replay of the last turn the store holds for the session' do
    record_turn
    replay = <<~TEXT.chomp
      02:00:00.000  prompt    Fix it
      02:00:01.000  preamble  Running the tests.
      02:00:01.000  dispatch  bash {"command":"bin/test"}
      02:00:02.000  finish    bash
      02:00:03.000  answer    All green.
    TEXT

    assert_equal [Riffer::Rig::Events::CommandOutput.new('trace', replay)], run_trace
  end

  it 'says so when the store holds no turn for the session' do
    assert_equal [Riffer::Rig::Events::CommandOutput.new('trace', 'No turn recorded yet')], run_trace
  end
end
