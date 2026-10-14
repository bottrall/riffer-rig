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

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: Array[String]
  def tokens(usage)
    cache = { cache_write: usage.cache_write_tokens, cache_read: usage.cache_read_tokens }
    [
      "↑#{usage.input_tokens}",
      "↓#{usage.output_tokens}",
      *cache.filter_map { |name, count| "#{name}:#{count}" if count&.positive? }
    ]
  end
end
