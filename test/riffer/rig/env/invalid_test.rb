# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Env::Invalid do
  it 'carries its message' do
    assert_equal 'RIFFER_MODEL: bad', Riffer::Rig::Env::Invalid.new('RIFFER_MODEL: bad').message
  end

  it 'is frozen' do
    assert_predicate Riffer::Rig::Env::Invalid.new('bad'), :frozen?
  end
end
