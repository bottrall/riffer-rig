# frozen_string_literal: true

class Riffer::Rig::Terminal::Replay::Turn
  # @dynamic heading, answer, stats, stop_reason
  attr_reader :heading #: String
  attr_reader :answer #: String
  attr_reader :stats #: Riffer::Rig::Terminal::TurnBuffer::Stats
  attr_reader :stop_reason #: Symbol?

  # @rbs heading: String
  # @rbs answer: String
  # @rbs stats: Riffer::Rig::Terminal::TurnBuffer::Stats
  # @rbs stop_reason: Symbol?
  # @rbs return: void
  def initialize(heading:, answer:, stats:, stop_reason:)
    @heading = heading
    @answer = answer
    @stats = stats
    @stop_reason = stop_reason
    freeze
  end
end
