# frozen_string_literal: true

module Riffer::Rig::Tools::Bash::MonotonicClock
  # @rbs return: Float
  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
