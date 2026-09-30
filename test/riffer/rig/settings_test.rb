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

  describe '.read' do
    it 'is empty when the file is absent' do
      Dir.mktmpdir do |dir|
        assert_empty Riffer::Rig::Settings.read(File.join(dir, 'settings.json'))
      end
    end

    it 'is empty for malformed json' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'settings.json')
        File.write(path, 'not json {{{')

        assert_empty Riffer::Rig::Settings.read(path)
      end
    end

    it 'is empty for a document that is not an object' do
      Dir.mktmpdir do |dir|
        assert_empty Riffer::Rig::Settings.read(settings_file(dir, %w[model]))
      end
    end

    it 'reads the document with symbol keys' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'model' => 'anthropic/claude-sonnet-4-6', 'git' => { 'depth' => 10 } })

        assert_equal({ model: 'anthropic/claude-sonnet-4-6', git: { depth: 10 } }, Riffer::Rig::Settings.read(path))
      end
    end
  end

  describe '.merge' do
    it 'lets the project override home key by key' do
      merged = Riffer::Rig::Settings.merge({ model: 'anthropic/a', reasoning: 'low' }, { model: 'openai/b' })

      assert_equal({ model: 'openai/b', reasoning: 'low' }, merged)
    end

    it 'merges nested extension namespaces key by key' do
      merged = Riffer::Rig::Settings.merge({ git: { depth: 10, remote: 'origin' } }, { git: { depth: 3 } })

      assert_equal({ depth: 3, remote: 'origin' }, merged[:git])
    end

    it 'replaces a project value that is not a namespace whole' do
      merged = Riffer::Rig::Settings.merge({ git: { depth: 10 } }, { git: 'off' })

      assert_equal 'off', merged[:git]
    end

    it 'replaces a home MCP server of the same name whole' do
      home = { mcp: { servers: { docs: { url: 'https://home.test', headers: { Authorization: 'secret' } } } } }
      project = { mcp: { servers: { docs: { url: 'https://project.test' } } } }

      assert_equal(
        { url: 'https://project.test' },
        Riffer::Rig::Settings.merge(home, project).dig(:mcp, :servers, :docs)
      )
    end

    it 'adds up the disabled lists of both scopes' do
      merged = Riffer::Rig::Settings.merge(
        { extensions: { disabled: %w[mcp] } },
        { extensions: { disabled: %w[skills mcp] } }
      )

      assert_equal %w[mcp skills], merged.dig(:extensions, :disabled)
    end

    it 'leaves the other extensions keys alone when adding up the disabled lists' do
      merged = Riffer::Rig::Settings.merge(
        { extensions: { disabled: %w[mcp], autoload: true } },
        { extensions: { disabled: %w[skills] } }
      )

      assert merged.dig(:extensions, :autoload)
    end
  end

  describe '.provider_for' do
    it 'returns the prefix' do
      assert_equal 'openai', Riffer::Rig::Settings.provider_for('openai/gpt-5-mini')
    end

    it 'returns the first segment of a name with slashes of its own' do
      assert_equal 'openrouter', Riffer::Rig::Settings.provider_for('openrouter/anthropic/claude-sonnet-4.6')
    end

    it 'is nil for a model without a slash' do
      assert_nil Riffer::Rig::Settings.provider_for('no-slash-model')
    end
  end

  describe '.rejection' do
    it 'is nil for a provider/name model string' do
      assert_nil Riffer::Rig::Settings.rejection('anthropic/claude-sonnet-4-6')
    end

    it 'rejects a bare model with the providers to choose from' do
      assert_equal(
        'sonnet is not a provider/name model string; the provider is one of: ' \
        'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter',
        Riffer::Rig::Settings.rejection('sonnet')
      )
    end

    it 'rejects a provider the registry does not know' do
      assert_match(%r{\Aacme/model is not a provider/name model string}, Riffer::Rig::Settings.rejection('acme/model'))
    end
  end

  describe '.model_options' do
    it 'includes cache control for an anthropic model' do
      assert_equal(
        { type: :ephemeral },
        Riffer::Rig::Settings.model_options('anthropic/claude-sonnet-4-6', nil)[:cache_control]
      )
    end

    it 'is empty for an openai model without reasoning' do
      assert_empty Riffer::Rig::Settings.model_options('openai/o3', nil)
    end

    it 'sets anthropic effort for low reasoning' do
      assert_equal 'low',
                   Riffer::Rig::Settings.model_options('anthropic/claude-sonnet-4-6', 'low')[:output_config][:effort]
    end

    it 'sets anthropic effort for max reasoning' do
      assert_equal 'max',
                   Riffer::Rig::Settings.model_options('anthropic/claude-sonnet-4-6', 'max')[:output_config][:effort]
    end

    it 'keeps cache control when anthropic reasoning is set' do
      assert_equal(
        { type: :ephemeral },
        Riffer::Rig::Settings.model_options('anthropic/claude-sonnet-4-6', 'low')[:cache_control]
      )
    end

    it 'sets reasoning effort for openai' do
      assert_equal 'high', Riffer::Rig::Settings.model_options('openai/o3', 'high')[:reasoning]
    end

    it 'sets reasoning effort for openrouter' do
      assert_equal 'xhigh',
                   Riffer::Rig::Settings.model_options('openrouter/anthropic/claude-sonnet-4.6', 'xhigh')[:reasoning]
    end

    it 'ignores an unrecognised reasoning value' do
      refute Riffer::Rig::Settings.model_options('openai/o3', 'turbo').key?(:reasoning)
    end

    it 'ignores max reasoning for openai' do
      refute Riffer::Rig::Settings.model_options('openai/o3', 'max').key?(:reasoning)
    end

    it 'ignores reasoning for a provider without support' do
      assert_empty Riffer::Rig::Settings.model_options('gemini/gemini-2.5-flash', 'high')
    end
  end

  describe '.store_model' do
    it 'writes the model' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, '.riffer', 'settings.json')
        Riffer::Rig::Settings.store_model('openai/gpt-5', path: path)

        assert_equal 'openai/gpt-5', JSON.parse(File.read(path))['model']
      end
    end

    it 'keeps the other keys' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'model' => 'anthropic/a', 'reasoning' => 'low' })
        Riffer::Rig::Settings.store_model('openai/gpt-5', path: path)

        assert_equal 'low', JSON.parse(File.read(path))['reasoning']
      end
    end
  end

  describe 'provider blocks' do
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

    it 'store provider keeps the other keys' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'model' => 'openai/o3' })

        Riffer::Rig::Settings.store_provider('openai', { 'base_url' => 'https://new.test' }, path: path)

        assert_equal 'openai/o3', JSON.parse(File.read(path))['model']
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
  end
end
