# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Events::BeforeToolCall do
  it 'freezes its args' do
    event = Riffer::Rig::Events::BeforeToolCall.new('call_1', 'bash', { command: 'ls' }, 1.5)

    assert_predicate event.args, :frozen?
  end

  it 'leaves the args it was given unfrozen' do
    args = { command: 'ls' }

    Riffer::Rig::Events::BeforeToolCall.new('call_1', 'bash', args, 1.5)

    refute_predicate args, :frozen?
  end
end
