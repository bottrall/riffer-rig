# frozen_string_literal: true

require 'test_helper'

class Riffer::Rig::Settings::PricingTest < Minitest::Test
  def test_exposes_input_price
    pricing = Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3)

    assert_in_delta 3.0, pricing.input
  end

  def test_exposes_output_price
    pricing = Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3)

    assert_in_delta 15.0, pricing.output
  end

  def test_exposes_cache_write_price
    pricing = Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3)

    assert_in_delta 3.75, pricing.cache_write
  end

  def test_exposes_cache_read_price
    pricing = Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3)

    assert_in_delta 0.3, pricing.cache_read
  end

  def test_input_is_read_only
    pricing = Riffer::Rig::Settings::Pricing.new(input: 3.0, output: 15.0, cache_write: 3.75, cache_read: 0.3)

    assert_raises(NoMethodError) { pricing.input = 1.0 }
  end
end
