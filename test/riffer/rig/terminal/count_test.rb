# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Count do
  it 'shows a count under a thousand in full' do
    assert_equal '999', Riffer::Rig::Terminal::Count.call(999)
  end

  it 'rounds thousands down to a decimal place' do
    assert_equal '18.2k', Riffer::Rig::Terminal::Count.call(18_290)
  end

  it 'drops the decimal of a whole thousand' do
    assert_equal '132k', Riffer::Rig::Terminal::Count.call(132_000)
  end

  it 'drops the decimal once a thousand count fills its slot' do
    assert_equal '132k', Riffer::Rig::Terminal::Count.call(132_500)
  end

  it 'drops the decimal once a million count fills its slot' do
    assert_equal '132M', Riffer::Rig::Terminal::Count.call(132_500_000)
  end

  it 'rounds millions down to a decimal place' do
    assert_equal '2.3M', Riffer::Rig::Terminal::Count.call(2_390_000)
  end

  it 'drops the decimal of a whole million' do
    assert_equal '1M', Riffer::Rig::Terminal::Count.call(1_000_000)
  end

  it 'shows a cost as an estimate to four decimal places' do
    assert_equal '~$0.2500', Riffer::Rig::Terminal::Count.cost(0.25)
  end
end
