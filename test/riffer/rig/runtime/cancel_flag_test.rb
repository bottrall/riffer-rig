# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::CancelFlag do
  it 'starts unset' do
    refute_predicate Riffer::Rig::Runtime::CancelFlag.new, :set?
  end

  it 'is set from another thread' do
    flag = Riffer::Rig::Runtime::CancelFlag.new
    Thread.new { flag.set }.join

    assert_predicate flag, :set?
  end

  it 'clears' do
    flag = Riffer::Rig::Runtime::CancelFlag.new
    flag.set
    flag.clear

    refute_predicate flag, :set?
  end
end
