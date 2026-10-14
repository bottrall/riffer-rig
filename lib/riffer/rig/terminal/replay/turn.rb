# frozen_string_literal: true

class Riffer::Rig::Terminal::Replay::Turn
  # @dynamic prompt, answer, stats
  attr_reader :prompt #: String
  attr_reader :answer #: String?
  attr_reader :stats #: Riffer::Rig::Terminal::TurnBuffer::Stats

  # @rbs prompt: String
  # @rbs answer: String?
  # @rbs stats: Riffer::Rig::Terminal::TurnBuffer::Stats
  # @rbs return: void
  def initialize(prompt:, answer:, stats:)
    @prompt = prompt
    @answer = answer
    @stats = stats
    freeze
  end

  # The record keeps no trace of how a turn ended.
  # @rbs return: bool
  def interrupted? = false
end
