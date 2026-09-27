# frozen_string_literal: true

class Riffer::Rig::TokenTally
  # @rbs @rates: Riffer::Config::Pricing::Rates?
  # @rbs @usage: Riffer::Providers::TokenUsage

  # @dynamic usage
  attr_reader :usage #: Riffer::Providers::TokenUsage

  # @rbs pricing: Riffer::Rig::Settings::Pricing?
  # @rbs return: void
  def initialize(pricing: nil)
    @rates = pricing && Riffer::Config::Pricing::Rates.new(
      input: pricing.input,
      output: pricing.output,
      cache_read: pricing.cache_read,
      cache_write: pricing.cache_write
    )
    @usage = price(Riffer::Providers::TokenUsage.new(input_tokens: 0, output_tokens: 0))
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: Riffer::Providers::TokenUsage
  def add(usage)
    priced = price(usage)
    @usage += priced
    priced
  end

  # @rbs return: Integer
  def input_tokens
    @usage.input_tokens
  end

  # @rbs return: Integer
  def output_tokens
    @usage.output_tokens
  end

  # @rbs return: Integer
  def cache_write_tokens
    @usage.cache_write_tokens || 0
  end

  # @rbs return: Integer
  def cache_read_tokens
    @usage.cache_read_tokens || 0
  end

  # @rbs return: Integer
  def total_tokens
    input_tokens + output_tokens + cache_write_tokens + cache_read_tokens
  end

  # @rbs return: bool
  def any?
    total_tokens.positive?
  end

  # @rbs return: Float?
  def estimated_cost
    @usage.cost
  end

  private

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: Riffer::Providers::TokenUsage
  def price(usage)
    rates = @rates
    return usage unless rates

    Riffer::Providers::TokenUsage.new(
      input_tokens: usage.input_tokens,
      output_tokens: usage.output_tokens,
      cache_write_tokens: usage.cache_write_tokens,
      cache_read_tokens: usage.cache_read_tokens,
      cost: rates.cost_for(
        input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens,
        cache_read_tokens: usage.cache_read_tokens,
        cache_write_tokens: usage.cache_write_tokens
      )
    )
  end
end
