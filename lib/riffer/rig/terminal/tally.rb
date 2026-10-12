# frozen_string_literal: true

module Riffer::Rig::Terminal::Tally
  extend self

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: String
  def call(usage)
    cost = usage.cost
    ["#{usage.total_tokens} tok", *(format('~$%.4f', cost) if cost)].join(' · ')
  end
end
