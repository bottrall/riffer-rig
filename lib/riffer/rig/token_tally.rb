# frozen_string_literal: true

class Riffer::Rig::TokenTally
  # @rbs @input_tokens: Integer
  # @rbs @output_tokens: Integer
  # @rbs @cache_write_tokens: Integer
  # @rbs @cache_read_tokens: Integer
  # @rbs @pricing: Riffer::Rig::Settings::Pricing?

  # @dynamic input_tokens, output_tokens, cache_write_tokens, cache_read_tokens
  attr_reader :input_tokens, :output_tokens, :cache_write_tokens, :cache_read_tokens

  # @rbs pricing: Riffer::Rig::Settings::Pricing?
  # @rbs return: void
  def initialize(pricing: nil)
    @pricing = pricing
    @input_tokens = 0
    @output_tokens = 0
    @cache_write_tokens = 0
    @cache_read_tokens = 0
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: void
  def add(usage)
    @input_tokens += usage.input_tokens
    @output_tokens += usage.output_tokens
    @cache_write_tokens += usage.cache_write_tokens || 0
    @cache_read_tokens += usage.cache_read_tokens || 0
  end

  # @rbs return: Integer
  def total_tokens
    @input_tokens + @output_tokens + @cache_write_tokens + @cache_read_tokens
  end

  # @rbs return: bool
  def any?
    total_tokens.positive?
  end

  # @rbs return: Float?
  def estimated_cost
    pricing = @pricing
    return nil unless pricing

    (
      (@input_tokens       * pricing.input) +
      (@output_tokens      * pricing.output)       +
      (@cache_write_tokens * pricing.cache_write)  +
      (@cache_read_tokens  * pricing.cache_read)
    ) / 1_000_000.0
  end
end
