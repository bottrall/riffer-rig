# frozen_string_literal: true

# Accumulates token usage across multiple turns in a session and computes an
# estimated cost based on a pricing object sourced from
# +Riffer::Rig::Settings+.
#
# Instantiate once per REPL session, call +add+ after each turn, then read
# +total_tokens+ and +estimated_cost+ for display.
#
#   pricing = Riffer::Rig::Settings.pricing_for('anthropic/claude-sonnet-4-6')
#   tally = Riffer::Rig::TokenTally.new(pricing: pricing)
#   tally.add(usage)
#   tally.estimated_cost  # => 0.000042  (USD), or nil if pricing is nil
#
class Riffer::Rig::TokenTally
  # @rbs @input_tokens: Integer
  # @rbs @output_tokens: Integer
  # @rbs @cache_write_tokens: Integer
  # @rbs @cache_read_tokens: Integer
  # @rbs @pricing: Riffer::Rig::Settings::Pricing?

  attr_reader :input_tokens, :output_tokens, :cache_write_tokens, :cache_read_tokens

  # @rbs ?pricing: Riffer::Rig::Settings::Pricing?
  # @rbs return: void
  def initialize(pricing: nil)
    @pricing = pricing
    @input_tokens = 0
    @output_tokens = 0
    @cache_write_tokens = 0
    @cache_read_tokens = 0
  end

  # Accumulates token counts from a +Riffer::Providers::TokenUsage+ object.
  #
  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: void
  def add(usage)
    @input_tokens += usage.input_tokens
    @output_tokens += usage.output_tokens
    @cache_write_tokens += usage.cache_write_tokens || 0
    @cache_read_tokens += usage.cache_read_tokens || 0
  end

  # Returns the total token count across all categories.
  #
  # @rbs return: Integer
  def total_tokens
    @input_tokens + @output_tokens + @cache_write_tokens + @cache_read_tokens
  end

  # Returns +true+ if any tokens have been counted.
  #
  # @rbs return: bool
  def any?
    total_tokens.positive?
  end

  # Returns the estimated cost in USD, or +nil+ if no pricing was provided.
  #
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
