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
        "sonnet is not a provider/name model string; the provider is one of: #{Riffer::Rig::Providers.list}",
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

  describe '.reasoning_rejection' do
    def rejection(level, model)
      Riffer::Rig::Settings::ModelOptions.reasoning_rejection(level, model)
    end

    it 'is nil for a level the provider accepts' do
      assert_nil rejection('high', 'openai/o3')
    end

    it 'names the levels the provider accepts' do
      assert_equal(
        'turbo is not a reasoning level openai/o3 accepts; it accepts: low medium high xhigh',
        rejection('turbo', 'openai/o3')
      )
    end

    it 'names max for an anthropic model' do
      assert_equal(
        'turbo is not a reasoning level anthropic/claude-sonnet-4-6 accepts; it accepts: low medium high xhigh max',
        rejection('turbo', 'anthropic/claude-sonnet-4-6')
      )
    end

    it 'rejects any level for a provider without support' do
      assert_equal 'gemini/gemini-2.5-flash accepts no reasoning level', rejection('high', 'gemini/gemini-2.5-flash')
    end
  end

  describe '.levels_for' do
    it 'lists the provider levels' do
      assert_equal %w[low medium high xhigh max],
                   Riffer::Rig::Settings::ModelOptions.levels_for('anthropic/claude-sonnet-4-6')
    end

    it 'is empty for a provider without support' do
      assert_empty Riffer::Rig::Settings::ModelOptions.levels_for('gemini/gemini-2.5-flash')
    end

    it 'is empty for a model without a provider' do
      assert_empty Riffer::Rig::Settings::ModelOptions.levels_for('sonnet')
    end
  end

  describe '.model_options' do
    it 'includes cache control for an anthropic model' do
      assert_equal({ cache_control: { type: :ephemeral } }, Riffer::Rig::Settings::ModelOptions.model_options('anthropic/claude-sonnet-4-6'))
    end

    it 'is empty for an openai model' do
      assert_empty Riffer::Rig::Settings::ModelOptions.model_options('openai/o3')
    end

    it 'is empty for a model without a provider' do
      assert_empty Riffer::Rig::Settings::ModelOptions.model_options('sonnet')
    end
  end
end
