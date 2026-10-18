# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Stores::ReasoningEntry do
  def entry(level = 'high')
    Riffer::Rig::Stores::ReasoningEntry.new(reasoning: level)
  end

  describe '#to_h' do
    it 'serialises the disk line' do
      assert_equal({ type: 'reasoning', reasoning: 'high', recorded_at: nil }, entry.to_h)
    end
  end

  describe 'equality' do
    it 'equals an entry with the same level' do
      assert_equal entry, entry
    end

    it 'differs when the level differs' do
      refute_equal entry, entry('low')
    end
  end

  it 'exposes the level' do
    assert_equal 'high', entry.reasoning
  end

  describe 'recorded_at' do
    def stamped
      Riffer::Rig::Stores::ReasoningEntry.new(reasoning: 'high', recorded_at: '2026-10-11T12:00:00.500Z')
    end

    it 'serialises into the disk line' do
      assert_equal({ type: 'reasoning', reasoning: 'high', recorded_at: '2026-10-11T12:00:00.500Z' }, stamped.to_h)
    end

    it 'survives a round trip' do
      assert_equal stamped.recorded_at, Riffer::Rig::Stores::ReasoningEntry.from_hash(stamped.to_h).recorded_at
    end

    it 'reads a line written without one as unstamped' do
      assert_nil Riffer::Rig::Stores::ReasoningEntry.from_hash({ type: 'reasoning', reasoning: 'high' }).recorded_at
    end

    it 'differs from the same entry unstamped' do
      refute_equal entry, stamped
    end
  end

  describe '.from_hash' do
    it 'returns nil when the level is missing' do
      assert_nil Riffer::Rig::Stores::ReasoningEntry.from_hash({ type: 'reasoning' })
    end

    it 'returns nil when the level is not a string' do
      assert_nil Riffer::Rig::Stores::ReasoningEntry.from_hash({ type: 'reasoning', reasoning: 3 })
    end

    it 'rebuilds the entry' do
      assert_equal entry, Riffer::Rig::Stores::ReasoningEntry.from_hash(entry.to_h)
    end
  end

  it 'is frozen' do
    assert_predicate entry, :frozen?
  end
end
