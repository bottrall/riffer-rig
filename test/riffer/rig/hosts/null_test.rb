# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Hosts::Null do
  it 'implements every host method' do
    assert_implements Riffer::Rig::Hosts::Base, Riffer::Rig::Hosts::Null
  end

  it 'declines every capability' do
    assert_empty Riffer::Rig::Hosts::Null.new.capabilities
  end

  it 'answers nil from ask' do
    assert_nil Riffer::Rig::Hosts::Null.new.ask('hello')
  end

  it 'answers false from confirm' do
    refute Riffer::Rig::Hosts::Null.new.confirm('sure?')
  end

  it 'treats notify as a no-op' do
    assert_nil Riffer::Rig::Hosts::Null.new.notify('hi', level: :warn)
  end

  it 'yields from progress' do
    yielded = false
    Riffer::Rig::Hosts::Null.new.progress('working') { yielded = true }

    assert yielded
  end
end
