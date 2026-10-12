# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Stores::ModelEntry do
  def entry(model = 'mock/other')
    Riffer::Rig::Stores::ModelEntry.new(model: model)
  end

  it 'exposes the model' do
    assert_equal 'mock/other', entry.model
  end

  it 'is frozen' do
    assert_predicate entry, :frozen?
  end

  describe '.from_hash' do
    it 'rebuilds the entry' do
      assert_equal entry, Riffer::Rig::Stores::ModelEntry.from_hash(entry.to_h)
    end

    it 'returns nil when the model is missing' do
      assert_nil Riffer::Rig::Stores::ModelEntry.from_hash({ type: 'model' })
    end

    it 'returns nil when the model is not a string' do
      assert_nil Riffer::Rig::Stores::ModelEntry.from_hash({ type: 'model', model: 123 })
    end
  end

  describe '#to_h' do
    it 'serialises the disk line' do
      assert_equal({ type: 'model', model: 'mock/other', recorded_at: nil }, entry.to_h)
    end
  end

  describe 'equality' do
    it 'equals an entry with the same model' do
      assert_equal entry, entry
    end

    it 'differs when the model differs' do
      refute_equal entry, entry('mock/test')
    end
  end

  describe 'recorded_at' do
    def stamped
      Riffer::Rig::Stores::ModelEntry.new(model: 'mock/other', recorded_at: '2026-10-11T12:00:00.500Z')
    end

    it 'is nil unless stamped' do
      assert_nil entry.recorded_at
    end

    it 'serialises into the disk line' do
      assert_equal({ type: 'model', model: 'mock/other', recorded_at: '2026-10-11T12:00:00.500Z' }, stamped.to_h)
    end

    it 'survives a round trip' do
      assert_equal stamped.recorded_at, Riffer::Rig::Stores::ModelEntry.from_hash(stamped.to_h).recorded_at
    end

    it 'reads a line written without one as unstamped' do
      assert_nil Riffer::Rig::Stores::ModelEntry.from_hash({ type: 'model', model: 'mock/other' }).recorded_at
    end

    it 'differs from the same entry unstamped' do
      refute_equal entry, stamped
    end
  end
end
