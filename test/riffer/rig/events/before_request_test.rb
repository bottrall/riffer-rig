# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Events::BeforeRequest do
  it 'freezes its messages' do
    event = Riffer::Rig::Events::BeforeRequest.new([Riffer::Messages::User.new('hi')])

    assert_predicate event.messages, :frozen?
  end

  it 'leaves the messages it was given unfrozen' do
    messages = [Riffer::Messages::User.new('hi')]

    Riffer::Rig::Events::BeforeRequest.new(messages)

    refute_predicate messages, :frozen?
  end
end
