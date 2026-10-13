# frozen_string_literal: true

class Riffer::Rig::Terminal::TurnBuffer::Stats
  # @dynamic steps, wall_time, usage
  attr_reader :steps #: Integer
  attr_reader :wall_time #: Float
  attr_reader :usage #: Riffer::Providers::TokenUsage?

  # @rbs steps: Integer
  # @rbs wall_time: Float
  # @rbs usage: Riffer::Providers::TokenUsage?
  # @rbs return: void
  def initialize(steps:, wall_time:, usage:)
    @steps = steps
    @wall_time = wall_time
    @usage = usage
    freeze
  end
end
