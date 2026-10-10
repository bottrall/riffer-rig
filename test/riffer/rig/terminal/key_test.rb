# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Key do
  def key
    Riffer::Rig::Terminal::Key.new(:text, 'a')
  end

  it 'equals another key with the same name and text' do
    assert_equal Riffer::Rig::Terminal::Key.new(:text, 'a'), key
  end

  it 'differs from a key with another name' do
    refute_equal Riffer::Rig::Terminal::Key.new(:enter), key
  end

  it 'hashes identically to an equal key' do
    assert_equal Riffer::Rig::Terminal::Key.new(:text, 'a').hash, key.hash
  end

  it 'is frozen' do
    assert_predicate key, :frozen?
  end

  it 'round-trips through to_h' do
    assert_equal({ name: :text, text: 'a' }, key.to_h)
  end
end
