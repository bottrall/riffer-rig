# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'json'

describe Riffer::Rig::Settings do
  def settings_file(dir, data)
    path = File.join(dir, 'settings.json')
    File.write(path, JSON.generate(data))
    path
  end

  it 'returns default model when file is absent' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'settings.json')

      assert_equal Riffer::Rig::Settings::DEFAULT_MODEL, Riffer::Rig::Settings.model(path: path)
    end
  end

  it 'returns model from settings file' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'anthropic/claude-sonnet-4-6' })

      assert_equal 'anthropic/claude-sonnet-4-6', Riffer::Rig::Settings.model(path: path)
    end
  end

  it 'returns nil pricing when file is absent' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'settings.json')

      assert_nil Riffer::Rig::Settings.pricing_for('anthropic/claude-sonnet-4-6', path: path)
    end
  end

  it 'returns nil pricing for unconfigured model' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'models' => {} })

      assert_nil Riffer::Rig::Settings.pricing_for('anthropic/claude-opus-4', path: path)
    end
  end

  it 'returns input pricing for configured model' do
    Dir.mktmpdir do |dir|
      path = settings_file(
        dir,
        {
          'models' => {
            'anthropic/claude-sonnet-4-6' => {
              'input' => 3.0, 'output' => 15.0, 'cache_write' => 3.75, 'cache_read' => 0.3
            }
          }
        }
      )

      pricing = Riffer::Rig::Settings.pricing_for('anthropic/claude-sonnet-4-6', path: path)

      assert_in_delta(3.0, pricing.input)
    end
  end

  it 'returns output pricing for configured model' do
    Dir.mktmpdir do |dir|
      path = settings_file(
        dir,
        {
          'models' => {
            'anthropic/claude-sonnet-4-6' => {
              'input' => 3.0, 'output' => 15.0, 'cache_write' => 3.75, 'cache_read' => 0.3
            }
          }
        }
      )

      pricing = Riffer::Rig::Settings.pricing_for('anthropic/claude-sonnet-4-6', path: path)

      assert_in_delta(15.0, pricing.output)
    end
  end

  it 'returns cache write pricing for configured model' do
    Dir.mktmpdir do |dir|
      path = settings_file(
        dir,
        {
          'models' => {
            'anthropic/claude-sonnet-4-6' => {
              'input' => 3.0, 'output' => 15.0, 'cache_write' => 3.75, 'cache_read' => 0.3
            }
          }
        }
      )

      pricing = Riffer::Rig::Settings.pricing_for('anthropic/claude-sonnet-4-6', path: path)

      assert_in_delta(3.75, pricing.cache_write)
    end
  end

  it 'returns cache read pricing for configured model' do
    Dir.mktmpdir do |dir|
      path = settings_file(
        dir,
        {
          'models' => {
            'anthropic/claude-sonnet-4-6' => {
              'input' => 3.0, 'output' => 15.0, 'cache_write' => 3.75, 'cache_read' => 0.3
            }
          }
        }
      )

      pricing = Riffer::Rig::Settings.pricing_for('anthropic/claude-sonnet-4-6', path: path)

      assert_in_delta(0.3, pricing.cache_read)
    end
  end

  it 'returns default model for malformed json' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'settings.json')
      File.write(path, 'not json {{{')

      assert_equal Riffer::Rig::Settings::DEFAULT_MODEL, Riffer::Rig::Settings.model(path: path)
    end
  end

  it 'returns nil pricing for malformed json' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'settings.json')
      File.write(path, 'not json {{{')

      assert_nil Riffer::Rig::Settings.pricing_for('anthropic/claude-sonnet-4-6', path: path)
    end
  end

  it 'coerces input pricing to float' do
    Dir.mktmpdir do |dir|
      path = settings_file(
        dir,
        {
          'models' => {
            'anthropic/claude-sonnet-4-6' => {
              'input' => 3, 'output' => 15, 'cache_write' => 4, 'cache_read' => 0
            }
          }
        }
      )

      pricing = Riffer::Rig::Settings.pricing_for('anthropic/claude-sonnet-4-6', path: path)

      assert_kind_of Float, pricing.input
    end
  end

  it 'coerces cache read pricing to float' do
    Dir.mktmpdir do |dir|
      path = settings_file(
        dir,
        {
          'models' => {
            'anthropic/claude-sonnet-4-6' => {
              'input' => 3, 'output' => 15, 'cache_write' => 4, 'cache_read' => 0
            }
          }
        }
      )

      pricing = Riffer::Rig::Settings.pricing_for('anthropic/claude-sonnet-4-6', path: path)

      assert_kind_of Float, pricing.cache_read
    end
  end

  it 'provider fields returns the providers block for one provider' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'providers' => { 'azure_openai' => { 'endpoint' => 'https://azure.test' } } })

      assert_equal(
        { 'endpoint' => 'https://azure.test' },
        Riffer::Rig::Settings.provider_fields('azure_openai', path: path)
      )
    end
  end

  it 'provider fields is empty for a provider without a block' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'providers' => 'not a hash' })

      assert_empty Riffer::Rig::Settings.provider_fields('azure_openai', path: path)
    end
  end

  it 'store provider merges fields into an existing block' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'providers' => { 'openai' => { 'base_url' => 'https://old.test' } } })

      Riffer::Rig::Settings.store_provider('openai', { 'base_url' => 'https://new.test' }, path: path)

      assert_equal({ 'base_url' => 'https://new.test' }, Riffer::Rig::Settings.provider_fields('openai', path: path))
    end
  end

  it 'remove provider keeps the other blocks' do
    Dir.mktmpdir do |dir|
      path = settings_file(
        dir,
        { 'providers' => { 'openai' => { 'base_url' => 'https://proxy.test' },
                           'amazon_bedrock' => { 'region' => 'us-west-2' } } }
      )

      Riffer::Rig::Settings.remove_provider('openai', path: path)

      assert_equal({ 'amazon_bedrock' => { 'region' => 'us-west-2' } }, JSON.parse(File.read(path))['providers'])
    end
  end

  it 'remove provider writes nothing when the provider has no block' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'settings.json')

      Riffer::Rig::Settings.remove_provider('openai', path: path)

      refute_path_exists path
    end
  end

  it 'provider for returns anthropic prefix' do
    assert_equal 'anthropic', Riffer::Rig::Settings.provider_for('anthropic/claude-sonnet-4-6')
  end

  it 'provider for returns openai prefix' do
    assert_equal 'openai', Riffer::Rig::Settings.provider_for('openai/gpt-5-mini')
  end

  it 'provider for returns gemini prefix' do
    assert_equal 'gemini', Riffer::Rig::Settings.provider_for('gemini/gemini-2.5-flash')
  end

  it 'provider for returns openrouter prefix' do
    assert_equal 'openrouter', Riffer::Rig::Settings.provider_for('openrouter/anthropic/claude-sonnet-4.6')
  end

  it 'provider for returns nil for model without slash' do
    assert_nil Riffer::Rig::Settings.provider_for('no-slash-model')
  end

  it 'model options includes cache control for anthropic model' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'anthropic/claude-sonnet-4-6' })

      assert_equal({ type: :ephemeral }, Riffer::Rig::Settings.model_options(path: path)[:cache_control])
    end
  end

  it 'model options returns empty hash for openai model without reasoning' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'openai/o3' })

      assert_equal({}, Riffer::Rig::Settings.model_options(path: path))
    end
  end

  it 'model options returns empty hash when file is absent' do
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'settings.json')

      opts = Riffer::Rig::Settings.model_options(path: path)

      # Default model is Anthropic — expect cache_control only, no reasoning
      assert_equal({ cache_control: { type: :ephemeral } }, opts)
    end
  end

  it 'model options sets anthropic effort for low reasoning' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'anthropic/claude-sonnet-4-6', 'reasoning' => 'low' })

      assert_equal 'low', Riffer::Rig::Settings.model_options(path: path)[:output_config][:effort]
    end
  end

  it 'model options sets anthropic effort for medium reasoning' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'anthropic/claude-sonnet-4-6', 'reasoning' => 'medium' })

      assert_equal 'medium', Riffer::Rig::Settings.model_options(path: path)[:output_config][:effort]
    end
  end

  it 'model options sets anthropic effort for high reasoning' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'anthropic/claude-sonnet-4-6', 'reasoning' => 'high' })

      assert_equal 'high', Riffer::Rig::Settings.model_options(path: path)[:output_config][:effort]
    end
  end

  it 'model options retains cache control when anthropic reasoning is set' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'anthropic/claude-sonnet-4-6', 'reasoning' => 'low' })

      opts = Riffer::Rig::Settings.model_options(path: path)

      assert_equal({ type: :ephemeral }, opts[:cache_control])
    end
  end

  it 'model options sets reasoning effort for openai low' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'openai/o3', 'reasoning' => 'low' })

      assert_equal 'low', Riffer::Rig::Settings.model_options(path: path)[:reasoning]
    end
  end

  it 'model options sets reasoning effort for openai high' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'openai/o3', 'reasoning' => 'high' })

      assert_equal 'high', Riffer::Rig::Settings.model_options(path: path)[:reasoning]
    end
  end

  it 'model options sets reasoning effort for openrouter medium' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'openrouter/anthropic/claude-sonnet-4.6', 'reasoning' => 'medium' })

      assert_equal 'medium', Riffer::Rig::Settings.model_options(path: path)[:reasoning]
    end
  end

  it 'model options sets anthropic effort for xhigh reasoning' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'anthropic/claude-sonnet-4-6', 'reasoning' => 'xhigh' })

      assert_equal 'xhigh', Riffer::Rig::Settings.model_options(path: path)[:output_config][:effort]
    end
  end

  it 'model options sets anthropic effort for max reasoning' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'anthropic/claude-sonnet-4-6', 'reasoning' => 'max' })

      assert_equal 'max', Riffer::Rig::Settings.model_options(path: path)[:output_config][:effort]
    end
  end

  it 'model options sets reasoning effort for openai xhigh' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'openai/o3', 'reasoning' => 'xhigh' })

      assert_equal 'xhigh', Riffer::Rig::Settings.model_options(path: path)[:reasoning]
    end
  end

  it 'model options sets reasoning effort for openrouter xhigh' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'openrouter/anthropic/claude-sonnet-4.6', 'reasoning' => 'xhigh' })

      assert_equal 'xhigh', Riffer::Rig::Settings.model_options(path: path)[:reasoning]
    end
  end

  it 'model options ignores unrecognised reasoning value' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'openai/o3', 'reasoning' => 'turbo' })

      refute Riffer::Rig::Settings.model_options(path: path).key?(:reasoning)
    end
  end

  it 'model options ignores max reasoning for openai' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'openai/o3', 'reasoning' => 'max' })

      refute Riffer::Rig::Settings.model_options(path: path).key?(:reasoning)
    end
  end

  it 'model options ignores max reasoning for openrouter' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'openrouter/anthropic/claude-sonnet-4.6', 'reasoning' => 'max' })

      refute Riffer::Rig::Settings.model_options(path: path).key?(:reasoning)
    end
  end

  it 'model options ignores reasoning key for provider without support' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'gemini/gemini-2.5-flash', 'reasoning' => 'high' })

      refute Riffer::Rig::Settings.model_options(path: path).key?(:reasoning)
    end
  end

  it 'model options ignores output config for provider without support' do
    Dir.mktmpdir do |dir|
      path = settings_file(dir, { 'model' => 'gemini/gemini-2.5-flash', 'reasoning' => 'high' })

      refute Riffer::Rig::Settings.model_options(path: path).key?(:output_config)
    end
  end
end
