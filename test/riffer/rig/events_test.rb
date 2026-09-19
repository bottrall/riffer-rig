# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Events do
  it 'types and round-trips a session_start' do
    event = Riffer::Rig::Events::SessionStart.new('0198-test', :new)

    assert_equal({ id: '0198-test', reason: :new, type: :session_start }, event.to_h)
  end

  it 'types and round-trips a session_end' do
    event = Riffer::Rig::Events::SessionEnd.new(:close)

    assert_equal({ reason: :close, type: :session_end }, event.to_h)
  end

  it 'types and round-trips a command_output' do
    event = Riffer::Rig::Events::CommandOutput.new('/model', 'switched')

    assert_equal({ command: '/model', text: 'switched', type: :command_output }, event.to_h)
  end

  it 'types and round-trips a skill_activated' do
    event = Riffer::Rig::Events::SkillActivated.new('review')

    assert_equal({ name: 'review', type: :skill_activated }, event.to_h)
  end

  it 'types and round-trips a notify' do
    event = Riffer::Rig::Events::Notify.new('boom', :error)

    assert_equal({ message: 'boom', level: :error, type: :notify }, event.to_h)
  end

  it 'types and round-trips a turn_end' do
    event = Riffer::Rig::Events::TurnEnd.new(:completed, nil)

    assert_equal({ stop_reason: :completed, usage: nil, type: :turn_end }, event.to_h)
  end

  it 'carries the cost of a turn_end with usage' do
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5, cost: 0.0001)

    event = Riffer::Rig::Events::TurnEnd.new(:completed, usage)

    assert_in_delta(0.0001, event.cost)
  end

  it 'leaves the cost nil without usage' do
    event = Riffer::Rig::Events::TurnEnd.new(:completed, nil)

    assert_nil event.cost
  end

  it 'freezes events at construction' do
    event = Riffer::Rig::Events::Notify.new('x', :info)

    assert_predicate event, :frozen?
  end

  it 'compares by value' do
    event = Riffer::Rig::Events::Notify.new('x', :info)

    assert_equal Riffer::Rig::Events::Notify.new('x', :info), event
  end
end
