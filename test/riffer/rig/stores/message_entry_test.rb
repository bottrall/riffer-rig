# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Stores::MessageEntry do
  def entry(message = { role: 'user', content: 'hello' })
    Riffer::Rig::Stores::MessageEntry.new(message: message)
  end

  it 'exposes the message payload' do
    assert_equal({ role: 'user', content: 'hello' }, entry.message)
  end

  it 'is frozen' do
    assert_predicate entry, :frozen?
  end

  describe '.from_hash' do
    it 'rebuilds the entry' do
      assert_equal entry, Riffer::Rig::Stores::MessageEntry.from_hash(entry.to_h)
    end

    it 'returns nil when the message is missing' do
      assert_nil Riffer::Rig::Stores::MessageEntry.from_hash({ type: 'message' })
    end

    it 'returns nil when the message is not a hash' do
      assert_nil Riffer::Rig::Stores::MessageEntry.from_hash({ type: 'message', message: 'hello' })
    end
  end

  describe '#to_h' do
    it 'serialises the disk line' do
      assert_equal({ type: 'message', message: { role: 'user', content: 'hello' } }, entry.to_h)
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
end
