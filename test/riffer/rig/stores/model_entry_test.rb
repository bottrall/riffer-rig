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
      assert_equal({ type: 'model', model: 'mock/other' }, entry.to_h)
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
end
