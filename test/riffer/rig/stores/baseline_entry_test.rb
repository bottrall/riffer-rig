# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Stores::BaselineEntry do
  def entry(system = %w[PROMPT CATALOG])
    Riffer::Rig::Stores::BaselineEntry.new(system: system, sections: { environment: 'ENV' })
  end

  it 'exposes the system texts' do
    assert_equal %w[PROMPT CATALOG], entry.system
  end

  it 'exposes the sections' do
    assert_equal({ environment: 'ENV' }, entry.sections)
  end

  describe '.from_hash' do
    it 'returns nil when the system texts are missing' do
      assert_nil Riffer::Rig::Stores::BaselineEntry.from_hash({ type: 'baseline', sections: {} })
    end

    it 'returns nil when a system text is not a string' do
      assert_nil Riffer::Rig::Stores::BaselineEntry.from_hash({ type: 'baseline', system: [1], sections: {} })
    end

    it 'returns nil when the sections are missing' do
      assert_nil Riffer::Rig::Stores::BaselineEntry.from_hash({ type: 'baseline', system: %w[PROMPT] })
    end

    it 'returns nil when a section is not a string' do
      line = { type: 'baseline', system: %w[PROMPT], sections: { environment: 1 } }

      assert_nil Riffer::Rig::Stores::BaselineEntry.from_hash(line)
    end

    it 'rebuilds the entry' do
      assert_equal entry, Riffer::Rig::Stores::BaselineEntry.from_hash(entry.to_h)
    end
  end

  it 'is frozen' do
    assert_predicate entry, :frozen?
  end

  describe '#to_h' do
    it 'serialises the disk line' do
      assert_equal(
        { type: 'baseline', system: %w[PROMPT CATALOG], sections: { environment: 'ENV' }, recorded_at: nil },
        entry.to_h
      )
    end
  end

  describe 'equality' do
    it 'equals an entry with the same values' do
      assert_equal entry, entry
    end

    it 'differs when the system texts differ' do
      refute_equal entry, entry(%w[PROMPT])
    end
  end

  describe 'recorded_at' do
    def stamped
      Riffer::Rig::Stores::BaselineEntry.new(
        system: %w[PROMPT], sections: { environment: 'ENV' }, recorded_at: '2026-10-11T12:00:00.500Z'
      )
    end

    it 'survives a round trip' do
      assert_equal stamped.recorded_at, Riffer::Rig::Stores::BaselineEntry.from_hash(stamped.to_h).recorded_at
    end

    it 'reads a line written without one as unstamped' do
      line = { type: 'baseline', system: %w[PROMPT], sections: {} }

      assert_nil Riffer::Rig::Stores::BaselineEntry.from_hash(line).recorded_at
    end
  end
end
