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
    it 'reads recorded_at back as the time it was stamped with' do
      time = Time.utc(2026, 10, 11, 2)

      assert_equal time, StampedNote.new(Riffer::Rig::Stores::Timestamp.dump(time)).recorded_time
    end
  end
end
