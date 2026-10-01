# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Settings::Document do
  let(:pricing) do
    { models: { 'anthropic/claude-sonnet-4-6': { input: 3, output: 15.0, cache_write: 3.75, cache_read: 0 } } }
  end

  it 'reads the model' do
    assert_equal 'openai/o3', Riffer::Rig::Settings::Document.new({ model: 'openai/o3' }).model
  end

  it 'ignores a model that is not a string' do
    assert_nil Riffer::Rig::Settings::Document.new({ model: 42 }).model
  end

  it 'reads the reasoning level' do
    assert_equal 'high', Riffer::Rig::Settings::Document.new({ reasoning: 'high' }).reasoning
  end

  it 'keys the pricing table by model string' do
    assert_equal ['anthropic/claude-sonnet-4-6'], Riffer::Rig::Settings::Document.new(pricing).models.keys
  end

  it 'reads each price' do
    assert_in_delta(15.0, Riffer::Rig::Settings::Document.new(pricing).models['anthropic/claude-sonnet-4-6'].output)
  end

  it 'coerces prices to float' do
    assert_kind_of Float, Riffer::Rig::Settings::Document.new(pricing).models['anthropic/claude-sonnet-4-6'].input
  end

  it 'ignores a pricing entry that is not an object' do
    assert_empty Riffer::Rig::Settings::Document.new({ models: { 'openai/o3': 3 } }).models
  end

  it 'keys the provider blocks by identifier and field name' do
    document = Riffer::Rig::Settings::Document.new({ providers: { azure_openai: { endpoint: 'https://azure.test' } } })

    assert_equal({ 'azure_openai' => { 'endpoint' => 'https://azure.test' } }, document.providers)
  end

  it 'reads the disabled extensions' do
    assert_equal %w[mcp], Riffer::Rig::Settings::Document.new({ extensions: { disabled: ['mcp', 3] } }).disabled
  end

  it 'has no disabled extensions when the list is not an array' do
    assert_empty Riffer::Rig::Settings::Document.new({ extensions: { disabled: 'mcp' } }).disabled
  end

  it 'reads the autoload flag' do
    assert Riffer::Rig::Settings::Document.new({ extensions: { autoload: true } }).autoload
  end

  it 'leaves autoload off unless it is exactly true' do
    refute Riffer::Rig::Settings::Document.new({ extensions: { autoload: 'yes' } }).autoload
  end

  it 'has no autoload when the extensions block is not an object' do
    refute Riffer::Rig::Settings::Document.new({ extensions: true }).autoload
  end

  it 'is frozen' do
    assert_predicate Riffer::Rig::Settings::Document.new({}), :frozen?
  end
end
