# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::RequestGuardrail do
  before do
    @messages = [Riffer::Messages::User.new('hello')]
  end

  def process(*before_request)
    registered = Riffer::Rig::Registrar::EVENTS.to_h { |event| [event, []] }.merge(before_request: before_request)
    hooks = Riffer::Rig::Runtime::Hooks.new(registered, Riffer::Rig::Hosts::Null.new)
    Riffer::Rig::Runtime::RequestGuardrail.new(hooks: hooks).process_input(@messages, context: nil)
  end

  it 'blocks with the reason a hook gives' do
    result = process(->(_event) { [:block, 'offline'] })

    assert_equal [:block, 'offline'], [result.type, result.data]
  end

  it 'passes the messages through when no hook replaces them' do
    result = process

    assert_equal [:pass, @messages], [result.type, result.data]
  end

  it 'transforms the messages into the replacement a hook returns' do
    replacement = [*@messages, Riffer::Messages::User.new('note')]
    result = process(->(_event) { replacement })

    assert_equal [:transform, replacement], [result.type, result.data]
  end

  it 'hands riffer a copy of the replacement' do
    replacement = [*@messages, Riffer::Messages::User.new('note')]

    refute_same replacement, process(->(_event) { replacement }).data
  end
end
