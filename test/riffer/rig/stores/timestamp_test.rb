# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Stores::Timestamp do
  describe '.dump' do
    it 'passes a missing timestamp through' do
      assert_nil Riffer::Rig::Stores::Timestamp.dump(nil)
    end

    it 'serialises to UTC ISO 8601 with milliseconds' do
      time = Time.new(2026, 10, 11, 12, 0, 0.123456r, '+10:00')

      assert_equal '2026-10-11T02:00:00.123Z', Riffer::Rig::Stores::Timestamp.dump(time)
    end
  end

  describe '.load' do
    it 'reads a missing timestamp as nil' do
      assert_nil Riffer::Rig::Stores::Timestamp.load(nil)
    end

    it 'reads a non-string timestamp as nil' do
      assert_nil Riffer::Rig::Stores::Timestamp.load(1_700_000_000)
    end

    it 'reads back what dump wrote' do
      assert_equal Time.utc(2026, 10, 11, 2, 0, 0.123r), Riffer::Rig::Stores::Timestamp.load('2026-10-11T02:00:00.123Z')
    end

    it 'reads a malformed timestamp as nil' do
      assert_nil Riffer::Rig::Stores::Timestamp.load('yesterday')
    end
  end

  describe '.normalize' do
    it 'passes a missing timestamp through' do
      assert_nil Riffer::Rig::Stores::Timestamp.normalize(nil)
    end

    it 'drops a malformed timestamp' do
      assert_nil Riffer::Rig::Stores::Timestamp.normalize('yesterday')
    end

    it 'rewrites a timestamp in the form dump writes' do
      assert_equal '2026-10-11T02:00:00.123Z', Riffer::Rig::Stores::Timestamp.normalize('2026-10-11T12:00:00.123456+10:00')
    end
  end
end
