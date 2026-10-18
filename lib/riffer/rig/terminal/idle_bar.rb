# frozen_string_literal: true

module Riffer::Rig::Terminal::IdleBar
  extend self

  SEPARATOR = ' · ' #: String

  # @rbs model: String
  # @rbs tally: Riffer::Providers::TokenUsage?
  # @rbs now: Time
  # @rbs return: String
  def call(model:, tally:, now:)
    [model, odometer(tally), cost(tally), now.strftime('%H:%M')].compact.join(SEPARATOR)
  end

  private

  # @rbs tally: Riffer::Providers::TokenUsage?
  # @rbs return: String?
  def odometer(tally)
    return nil unless tally

    count = Riffer::Rig::Terminal::Count
    "↑#{count.call(tally.input_tokens)} ↓#{count.call(tally.output_tokens)} tok"
  end

  # @rbs tally: Riffer::Providers::TokenUsage?
  # @rbs return: String?
  def cost(tally)
    format('~$%.4f', tally.cost) if tally&.cost
  end
end
