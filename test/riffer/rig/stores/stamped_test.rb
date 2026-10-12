# frozen_string_literal: true

require 'test_helper'

class StampedNote
  extend Riffer::Rig::Support::TypedValue::Schema
  include Riffer::Rig::Support::TypedValue
  include Riffer::Rig::Stores::Stamped

  typed_value 'note', :text

  attr_reader :text

  def initialize(text, recorded_at: nil)
    @text = text
    @recorded_at = recorded_at
    freeze
  end
end

describe Riffer::Rig::Stores::Stamped do
  let(:recorded_at) { Time.utc(2026, 10, 11, 2, 0, 0.123r) }

  describe '#recorded_at' do
    it 'reads the time the value was stamped with' do
      assert_equal recorded_at, StampedNote.new('hi', recorded_at: recorded_at).recorded_at
    end
  end

  describe '#to_h' do
    it 'adds the dumped timestamp to the typed value hash' do
      assert_equal(
        { type: 'note', text: 'hi', recorded_at: '2026-10-11T02:00:00.123Z' },
        StampedNote.new('hi', recorded_at: recorded_at).to_h
      )
    end

    it 'omits the timestamp when unstamped' do
      assert_equal({ type: 'note', text: 'hi' }, StampedNote.new('hi').to_h)
    end
  end

  describe '#==' do
    it 'tells apart values stamped at different times' do
      refute_equal StampedNote.new('hi', recorded_at: recorded_at), StampedNote.new('hi')
    end
  end
end
