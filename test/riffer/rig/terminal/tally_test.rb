# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Tally do
  describe '.call' do
    it 'shows the token total alone when the usage is unpriced' do
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 300, output_tokens: 150)

      assert_equal '450 tok', Riffer::Rig::Terminal::Tally.call(usage)
    end

    it 'appends the cost when the usage is priced' do
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 300, output_tokens: 150, cost: 0.25)

      assert_equal '450 tok · ~$0.2500', Riffer::Rig::Terminal::Tally.call(usage)
    end
  end

  describe '.cost' do
    it 'is absent when the usage is unpriced' do
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 300, output_tokens: 150)

      assert_nil Riffer::Rig::Terminal::Tally.cost(usage)
    end

    it 'shows the cost of priced usage to four decimal places' do
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 300, output_tokens: 150, cost: 0.25)

      assert_equal '~$0.2500', Riffer::Rig::Terminal::Tally.cost(usage)
    end
  end

  describe '.tokens' do
    it 'shows the input and output tokens' do
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 50)

      assert_equal %w[↑100 ↓50], Riffer::Rig::Terminal::Tally.tokens(usage)
    end

    it 'adds the cache write tokens of usage that wrote to the cache' do
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 50, cache_write_tokens: 400)

      assert_equal %w[↑100 ↓50 cache_write:400], Riffer::Rig::Terminal::Tally.tokens(usage)
    end

    it 'adds the cache read tokens of usage that read from the cache' do
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 50, cache_read_tokens: 200)

      assert_equal %w[↑100 ↓50 cache_read:200], Riffer::Rig::Terminal::Tally.tokens(usage)
    end

    it 'omits a cache count of zero' do
      usage = Riffer::Providers::TokenUsage.new(
        input_tokens: 100, output_tokens: 50, cache_write_tokens: 0, cache_read_tokens: 0
      )

      assert_equal %w[↑100 ↓50], Riffer::Rig::Terminal::Tally.tokens(usage)
    end
  end
end
