# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Events::AfterToolCall do
  def event(args)
    Riffer::Rig::Events::AfterToolCall.new('call_1', 'bash', args, Riffer::Tools::Response.text('ok'), 4.5, 2.5)
  end

  it 'freezes its args' do
    assert_predicate event({ command: 'ls' }).args, :frozen?
  end

  it 'leaves the args it was given unfrozen' do
    args = { command: 'ls' }

    event(args)

    refute_predicate args, :frozen?
  end
end
