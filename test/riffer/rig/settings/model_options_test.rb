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
    def rejection(level)
      Riffer::Rig::Settings::ModelOptions.reasoning_rejection(level)
    end

    it 'is nil for a level riffer accepts' do
      assert_nil rejection('high')
    end

    it 'is nil for off' do
      assert_nil rejection('off')
    end

    it 'names the levels riffer accepts' do
      assert_equal(
        'turbo is not a reasoning level; riffer accepts: off low medium high xhigh max',
        rejection('turbo')
      )
    end
  end

  describe '.reasoning_level' do
    it 'is the level riffer accepts' do
      assert_equal 'high', Riffer::Rig::Settings::ModelOptions.reasoning_level('high')
    end

    it 'is nil for a level riffer does not accept' do
      assert_nil Riffer::Rig::Settings::ModelOptions.reasoning_level('turbo')
    end

    it 'is nil without a level' do
      assert_nil Riffer::Rig::Settings::ModelOptions.reasoning_level(nil)
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

  describe '.native_options' do
    it 'keeps the switch of a native tool the provider supports' do
      switches = { web_search: true }

      assert_equal switches, Riffer::Rig::Settings::ModelOptions.native_options('mock/test', switches)
    end

    it 'passes a switch object through as the option value' do
      switches = { web_search: { max_uses: 3 } }

      assert_equal switches, Riffer::Rig::Settings::ModelOptions.native_options('mock/test', switches)
    end

    it 'drops the switch of a native tool the provider does not support' do
      assert_empty Riffer::Rig::Settings::ModelOptions.native_options('gemini/gem-2.5-pro', { web_search: true })
    end

    it 'drops the switch of a native tool it does not know' do
      assert_empty Riffer::Rig::Settings::ModelOptions.native_options('mock/test', { code_interpreter: true })
    end

    it 'drops every switch for a model without a provider' do
      assert_empty Riffer::Rig::Settings::ModelOptions.native_options('sonnet', { web_search: true })
    end

    it 'is empty without a switch' do
      assert_empty Riffer::Rig::Settings::ModelOptions.native_options('mock/test', {})
    end
  end
end
