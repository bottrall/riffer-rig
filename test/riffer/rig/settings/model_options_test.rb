# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Settings::ModelOptions do
  describe '.provider_for' do
    it 'returns the prefix' do
      assert_equal 'openai', Riffer::Rig::Settings::ModelOptions.provider_for('openai/gpt-5-mini')
    end

    it 'returns the first segment of a name with slashes of its own' do
      assert_equal(
        'openrouter',
        Riffer::Rig::Settings::ModelOptions.provider_for('openrouter/anthropic/claude-sonnet-4.6')
      )
    end

    it 'is nil for a model without a slash' do
      assert_nil Riffer::Rig::Settings::ModelOptions.provider_for('no-slash-model')
    end
  end

  describe '.rejection' do
    it 'is nil for a provider/name model string' do
      assert_nil Riffer::Rig::Settings::ModelOptions.rejection('anthropic/claude-sonnet-4-6')
    end

    it 'rejects a bare model with the providers to choose from' do
      assert_equal(
        'sonnet is not a provider/name model string; the provider is one of: ' \
        'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter',
        Riffer::Rig::Settings::ModelOptions.rejection('sonnet')
      )
    end

    it 'rejects a provider the registry does not know' do
      assert_match(
        %r{\Aacme/model is not a provider/name model string},
        Riffer::Rig::Settings::ModelOptions.rejection('acme/model')
      )
    end
  end

  describe '.model_options' do
    def model_options(model, reasoning)
      Riffer::Rig::Settings::ModelOptions.model_options(model, reasoning)
    end

    it 'ignores reasoning for a model without a provider' do
      assert_empty model_options('sonnet', 'high')
    end

    it 'includes cache control for an anthropic model' do
      assert_equal({ type: :ephemeral }, model_options('anthropic/claude-sonnet-4-6', nil)[:cache_control])
    end

    it 'is empty for an openai model without reasoning' do
      assert_empty model_options('openai/o3', nil)
    end

    it 'sets anthropic effort for low reasoning' do
      assert_equal 'low', model_options('anthropic/claude-sonnet-4-6', 'low')[:output_config][:effort]
    end

    it 'sets anthropic effort for max reasoning' do
      assert_equal 'max', model_options('anthropic/claude-sonnet-4-6', 'max')[:output_config][:effort]
    end

    it 'keeps cache control when anthropic reasoning is set' do
      assert_equal({ type: :ephemeral }, model_options('anthropic/claude-sonnet-4-6', 'low')[:cache_control])
    end

    it 'sets reasoning effort for openai' do
      assert_equal 'high', model_options('openai/o3', 'high')[:reasoning]
    end

    it 'sets reasoning effort for openrouter' do
      assert_equal 'xhigh', model_options('openrouter/anthropic/claude-sonnet-4.6', 'xhigh')[:reasoning]
    end

    it 'ignores an unrecognised reasoning value' do
      refute model_options('openai/o3', 'turbo').key?(:reasoning)
    end

    it 'ignores max reasoning for openai' do
      refute model_options('openai/o3', 'max').key?(:reasoning)
    end

    it 'ignores reasoning for a provider without support' do
      assert_empty model_options('gemini/gemini-2.5-flash', 'high')
    end
  end
end
