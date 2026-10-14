# frozen_string_literal: true

module Riffer::Rig::Terminal::Tally
  extend self

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: String
  def call(usage)
    ["#{usage.total_tokens} tok", *cost(usage)].join(' · ')
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: String?
  def cost(usage)
    amount = usage.cost
    format('~$%.4f', amount) if amount
  end
end
