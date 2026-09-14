# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Host do
  it 'declines every capability' do
    assert_empty Riffer::Rig::Host.new.capabilities
  end

  it 'answers nil from ask' do
    assert_nil Riffer::Rig::Host.new.ask('hello')
  end

  it 'answers false from confirm' do
    refute Riffer::Rig::Host.new.confirm('sure?')
  end

  it 'treats notify as a no-op' do
    assert_nil Riffer::Rig::Host.new.notify('hi', level: :warn)
  end

  it 'yields from progress' do
    yielded = false
    Riffer::Rig::Host.new.progress('working') { yielded = true }

    assert yielded
  end
end
