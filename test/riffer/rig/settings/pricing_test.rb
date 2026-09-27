# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Settings::Pricing do
  def sonnet
    Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3)
  end

  it 'exposes the input price' do
    assert_in_delta 3.0, sonnet.input
  end

  it 'exposes the output price' do
    assert_in_delta 15.0, sonnet.output
  end

  it 'exposes the cache write price' do
    assert_in_delta 3.75, sonnet.cache_write
  end

  it 'exposes the cache read price' do
    assert_in_delta 0.3, sonnet.cache_read
  end

  it 'keeps the input price read-only' do
    assert_raises(NoMethodError) { sonnet.input = 1.0 }
  end

  describe '.register' do
    def registered_rates
      registry = Riffer::Config::Pricing.new
      Riffer::Rig::Settings::Pricing.register({ 'anthropic/claude-sonnet-4-6' => sonnet }, registry)
      registry.rates_for('anthropic/claude-sonnet-4-6')
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
  end
end
