# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Tools::Bash::MonotonicClock do
  def setup
    @clock = Object.new.extend(Riffer::Rig::Tools::Bash::MonotonicClock)
  end

  it 'reads the monotonic clock in seconds' do
    assert_in_delta Process.clock_gettime(Process::CLOCK_MONOTONIC), @clock.monotonic_now, 1.0
  end
end
