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

  it 'exposes the schema version' do
    assert_equal 1, header.schema_version
  end

  it 'exposes the session id' do
    assert_equal 'aaa', header.id
  end

  it 'exposes the session cwd' do
    assert_equal '/project', header.cwd
  end

  it 'exposes the creation time' do
    assert_equal '2026-01-01T00:00:00Z', header.created_at
  end

  it 'exposes the model' do
    assert_equal 'mock/test', header.model
  end

  it 'exposes the riffer rig version' do
    assert_equal '0.9.0', header.riffer_rig_version
  end

  it 'exposes the riffer version' do
    assert_equal '0.49.0', header.riffer_version
  end

  it 'exposes the title' do
    assert_equal 'hello', header.title
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

  describe '.from_hash' do
    it 'rebuilds the entry' do
      assert_equal header, Riffer::Rig::Stores::Header.from_hash(header.to_h)
    end

    it 'stamps the entry with the store-supplied updated' do
      assert_equal updated_time, Riffer::Rig::Stores::Header.from_hash(header.to_h, updated: updated_time).updated
    end

    it 'returns nil when a string field is missing' do
      assert_nil Riffer::Rig::Stores::Header.from_hash(header.to_h.except(:title))
    end

    it 'returns nil when a field is not a string' do
      assert_nil Riffer::Rig::Stores::Header.from_hash(header.to_h.merge(model: 123))
    end

    it 'returns nil when the schema version is not an integer' do
      assert_nil Riffer::Rig::Stores::Header.from_hash(header.to_h.merge(schema_version: '1'))
    end
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
    it 'equals a header with the same fields' do
      assert_equal header, header
    end

    it 'ignores the stamped updated' do
      assert_equal header, header(updated: updated_time)
    end

    it 'differs when a field differs' do
      refute_equal header, header(title: 'other')
    end

    it 'hashes equal for equal entries' do
      assert_equal header.hash, header(updated: updated_time).hash
    end
  end
end
