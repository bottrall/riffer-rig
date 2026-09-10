# frozen_string_literal: true

require 'test_helper'

SONNET_PRICING = Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3)

describe Riffer::Rig::TokenTally do
  def usage(input:, output:, cache_write: nil, cache_read: nil)
    Riffer::Providers::TokenUsage.new(
      input_tokens: input,
      output_tokens: output,
      cache_write_tokens: cache_write,
      cache_read_tokens: cache_read
    )
  end

  it 'starts with zero tokens' do
    tally = Riffer::Rig::TokenTally.new

    assert_equal 0, tally.total_tokens
  end

  it 'any returns false when empty' do
    tally = Riffer::Rig::TokenTally.new

    refute_predicate tally, :any?
  end

  it 'accumulates input tokens' do
    tally = Riffer::Rig::TokenTally.new(pricing: SONNET_PRICING)
    tally.add(usage(input: 100, output: 50))
    tally.add(usage(input: 200, output: 75))

    assert_equal 300, tally.input_tokens
  end

  it 'accumulates output tokens' do
    tally = Riffer::Rig::TokenTally.new(pricing: SONNET_PRICING)
    tally.add(usage(input: 100, output: 50))
    tally.add(usage(input: 200, output: 75))

    assert_equal 125, tally.output_tokens
  end

  it 'accumulates cache write tokens' do
    tally = Riffer::Rig::TokenTally.new(pricing: SONNET_PRICING)
    tally.add(usage(input: 0, output: 0, cache_write: 500, cache_read: 200))
    tally.add(usage(input: 0, output: 0, cache_write: 100, cache_read: 800))

    assert_equal 600, tally.cache_write_tokens
  end

  it 'accumulates cache read tokens' do
    tally = Riffer::Rig::TokenTally.new(pricing: SONNET_PRICING)
    tally.add(usage(input: 0, output: 0, cache_write: 500, cache_read: 200))
    tally.add(usage(input: 0, output: 0, cache_write: 100, cache_read: 800))

    assert_equal 1000, tally.cache_read_tokens
  end

  it 'handles nil cache tokens gracefully' do
    tally = Riffer::Rig::TokenTally.new(pricing: SONNET_PRICING)
    tally.add(usage(input: 10, output: 5))

    assert_equal 15, tally.total_tokens
  end

  it 'total tokens sums all categories' do
    tally = Riffer::Rig::TokenTally.new(pricing: SONNET_PRICING)
    tally.add(usage(input: 100, output: 50, cache_write: 400, cache_read: 200))

    assert_equal 750, tally.total_tokens
  end

  it 'any returns true after adding tokens' do
    tally = Riffer::Rig::TokenTally.new(pricing: SONNET_PRICING)
    tally.add(usage(input: 1, output: 0))

    assert_predicate tally, :any?
  end

  it 'estimated cost uses pricing' do
    tally = Riffer::Rig::TokenTally.new(pricing: SONNET_PRICING)
    # 1M input @ $3.0/M + 1M output @ $15.0/M = $18.0
    tally.add(usage(input: 1_000_000, output: 1_000_000))

    assert_in_delta 18.0, tally.estimated_cost, 0.0001
  end

  it 'estimated cost includes cache tokens' do
    tally = Riffer::Rig::TokenTally.new(pricing: SONNET_PRICING)
    # 1M cache_write @ $3.75/M + 1M cache_read @ $0.30/M = $4.05
    tally.add(usage(input: 0, output: 0, cache_write: 1_000_000, cache_read: 1_000_000))

    assert_in_delta 4.05, tally.estimated_cost, 0.0001
  end

  it 'estimated cost returns nil when no pricing provided' do
    tally = Riffer::Rig::TokenTally.new
    tally.add(usage(input: 100, output: 50))

    assert_nil tally.estimated_cost
  end
end
