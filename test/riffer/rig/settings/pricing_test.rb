# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Settings::Pricing do
  def sonnet
    Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3)
  end

  it 'exposes the input, output, cache write and cache read rates' do
    assert_equal [3.0, 15.0, 3.75, 0.3], [sonnet.input, sonnet.output, sonnet.cache_write, sonnet.cache_read]
  end

  describe '.from' do
    it 'reads every rate from its key' do
      pricing = Riffer::Rig::Settings::Pricing.from(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3)

      assert_equal [3.0, 15.0, 3.75, 0.3], [pricing.input, pricing.output, pricing.cache_write, pricing.cache_read]
    end

    it 'defaults absent rates to zero' do
      pricing = Riffer::Rig::Settings::Pricing.from(input: 3.0)

      assert_equal [3.0, 0.0, 0.0, 0.0], [pricing.input, pricing.output, pricing.cache_write, pricing.cache_read]
    end

    it 'stores every rate as a float' do
      pricing = Riffer::Rig::Settings::Pricing.from(input: 3, output: 15, cache_write: 4, cache_read: 1)

      assert_equal [Float] * 4, [pricing.input, pricing.output, pricing.cache_write, pricing.cache_read].map(&:class)
    end
  end

  describe '.register' do
    def registered_rates(model = 'anthropic/claude-sonnet-4-6')
      registry = Riffer::Config::Pricing.new
      Riffer::Rig::Settings::Pricing.register({ 'anthropic/claude-sonnet-4-6' => sonnet }, registry)
      registry.rates_for(model)
    end

    it 'registers the input rate under the model id' do
      assert_in_delta 3.0, registered_rates.input
    end

    it 'registers the output rate under the model id' do
      assert_in_delta 15.0, registered_rates.output
    end

    it 'registers the cache write rate under the model id' do
      assert_in_delta 3.75, registered_rates.cache_write
    end

    it 'registers the cache read rate under the model id' do
      assert_in_delta 0.3, registered_rates.cache_read
    end

    it 'prices the model in USD per million tokens' do
      assert_in_delta 6.0, registered_rates.cost_for(input_tokens: 1_000_000, output_tokens: 200_000)
    end

    it 'leaves a model outside the table unpriced' do
      assert_nil registered_rates('mock/test')
    end
  end
end
