# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Stores::MessageEntry do
  def entry(message = { role: 'user', content: 'hello' })
    Riffer::Rig::Stores::MessageEntry.new(message: message)
  end

  it 'exposes the message payload' do
    assert_equal({ role: 'user', content: 'hello' }, entry.message)
  end

  describe '.from_hash' do
    it 'returns nil when the message is missing' do
      assert_nil Riffer::Rig::Stores::MessageEntry.from_hash({ type: 'message' })
    end

    it 'returns nil when the message is not a hash' do
      assert_nil Riffer::Rig::Stores::MessageEntry.from_hash({ type: 'message', message: 'hello' })
    end

    it 'rebuilds the entry' do
      assert_equal entry, Riffer::Rig::Stores::MessageEntry.from_hash(entry.to_h)
    end
  end

  it 'is frozen' do
    assert_predicate entry, :frozen?
  end

  describe '#to_h' do
    it 'serialises the disk line' do
      assert_equal({ type: 'message', message: { role: 'user', content: 'hello' }, recorded_at: nil }, entry.to_h)
    end
  end

  describe 'equality' do
    it 'equals an entry with the same payload' do
      assert_equal entry, entry
    end

    it 'differs when the payload differs' do
      refute_equal entry, entry({ role: 'user', content: 'other' })
    end
  end

  describe 'recorded_at' do
    def stamped
      Riffer::Rig::Stores::MessageEntry.new(
        message: { role: 'user', content: 'hello' },
        recorded_at: '2026-10-11T12:00:00.500Z'
      )
    end

    it 'is nil unless stamped' do
      assert_nil entry.recorded_at
    end

    it 'serialises into the disk line' do
      assert_equal(
        { type: 'message', message: { role: 'user', content: 'hello' }, recorded_at: '2026-10-11T12:00:00.500Z' },
        stamped.to_h
      )
    end

    it 'survives a round trip' do
      assert_equal stamped.recorded_at, Riffer::Rig::Stores::MessageEntry.from_hash(stamped.to_h).recorded_at
    end

    it 'reads a line written without one as unstamped' do
      line = { type: 'message', message: { role: 'user', content: 'hello' } }

      assert_nil Riffer::Rig::Stores::MessageEntry.from_hash(line).recorded_at
    end

    it 'differs from the same entry unstamped' do
      refute_equal entry, stamped
    end
  end
end
