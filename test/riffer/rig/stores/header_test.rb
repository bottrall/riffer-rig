# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Stores::Header do
  def updated_time
    Time.at(1000)
  end

  def header(overrides = {})
    Riffer::Rig::Stores::Header.new(
      schema_version: 1,
      id: 'aaa',
      cwd: '/project',
      created_at: '2026-01-01T00:00:00Z',
      model: 'mock/test',
      riffer_rig_version: '0.9.0',
      riffer_version: '0.49.0',
      title: 'hello',
      **overrides
    )
  end

  describe '.from_hash' do
    it 'returns nil when the schema version is not an integer' do
      assert_nil Riffer::Rig::Stores::Header.from_hash(header.to_h.merge(schema_version: '1'))
    end

    it 'returns nil when a string field is missing' do
      assert_nil Riffer::Rig::Stores::Header.from_hash(header.to_h.except(:title))
    end

    it 'returns nil when a field is not a string' do
      assert_nil Riffer::Rig::Stores::Header.from_hash(header.to_h.merge(model: 123))
    end

    it 'rebuilds the entry' do
      assert_equal header, Riffer::Rig::Stores::Header.from_hash(header.to_h)
    end

    it 'stamps the entry with the store-supplied updated' do
      assert_equal updated_time, Riffer::Rig::Stores::Header.from_hash(header.to_h, updated: updated_time).updated
    end
  end

  it 'defaults updated to nil' do
    assert_nil header.updated
  end

  it 'carries the store-stamped updated' do
    assert_equal updated_time, header(updated: updated_time).updated
  end

  it 'is frozen' do
    assert_predicate header, :frozen?
  end

  describe '#to_h' do
    it 'serialises the disk line' do
      assert_equal(
        {
          type: 'header', schema_version: 1, id: 'aaa', cwd: '/project', created_at: '2026-01-01T00:00:00Z',
          model: 'mock/test', riffer_rig_version: '0.9.0', riffer_version: '0.49.0', title: 'hello'
        },
        header.to_h
      )
    end

    it 'leaves the store-derived updated out' do
      assert_nil header(updated: updated_time).to_h[:updated]
    end
  end

  describe 'equality' do
    it 'ignores the stamped updated' do
      assert_equal header, header(updated: updated_time)
    end

    it 'hashes equal for equal entries' do
      assert_equal header.hash, header(updated: updated_time).hash
    end
  end
end
