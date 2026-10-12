# frozen_string_literal: true

require 'test_helper'

class StampedNote
  include Riffer::Rig::Stores::Stamped

  attr_reader :recorded_at

  def initialize(recorded_at)
    @recorded_at = recorded_at
    freeze
  end
end

describe Riffer::Rig::Stores::Stamped do
  describe '#recorded_time' do
    it 'parses the recorded_at string' do
      assert_equal Time.utc(2026, 10, 11, 2, 0, 0.123r), StampedNote.new('2026-10-11T02:00:00.123Z').recorded_time
    end
  end
end
