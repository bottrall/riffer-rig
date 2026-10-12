# frozen_string_literal: true

require 'test_helper'
require 'json'

describe Riffer::Rig::Credentials::ProviderFields do
  def settings_file(dir, data)
    path = File.join(dir, 'settings.json')
    File.write(path, JSON.generate(data))
    path
  end

  describe '.read' do
    it 'returns the providers block for one provider' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'providers' => { 'azure_openai' => { 'endpoint' => 'https://azure.test' } } })

        assert_equal(
          { 'endpoint' => 'https://azure.test' },
          Riffer::Rig::Credentials::ProviderFields.read('azure_openai', path: path)
        )
      end
    end

    it 'is empty for a provider without a block' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'providers' => { 'amazon_bedrock' => { 'region' => 'us-west-2' } } })

        assert_empty Riffer::Rig::Credentials::ProviderFields.read('azure_openai', path: path)
      end
    end
  end

  describe '.store' do
    it 'merges fields into an existing block' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'providers' => { 'openai' => { 'base_url' => 'https://old.test' } } })

        Riffer::Rig::Credentials::ProviderFields.store('openai', { 'base_url' => 'https://new.test' }, path: path)

        assert_equal(
          { 'base_url' => 'https://new.test' },
          Riffer::Rig::Credentials::ProviderFields.read('openai', path: path)
        )
      end
    end

    it 'adds the block when the provider has none' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'providers' => { 'amazon_bedrock' => { 'region' => 'us-west-2' } } })

        Riffer::Rig::Credentials::ProviderFields.store('openai', { 'base_url' => 'https://new.test' }, path: path)

        assert_equal(
          { 'base_url' => 'https://new.test' },
          Riffer::Rig::Credentials::ProviderFields.read('openai', path: path)
        )
      end
    end

    it 'keeps the stored fields the store does not name' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'providers' => { 'openai' => { 'api_key_env' => 'OPENAI_KEY' } } })

        Riffer::Rig::Credentials::ProviderFields.store('openai', { 'base_url' => 'https://new.test' }, path: path)

        assert_equal(
          { 'api_key_env' => 'OPENAI_KEY', 'base_url' => 'https://new.test' },
          Riffer::Rig::Credentials::ProviderFields.read('openai', path: path)
        )
      end
    end

    it 'keeps the other keys' do
      Dir.mktmpdir do |dir|
        path = settings_file(dir, { 'model' => 'openai/o3' })

        Riffer::Rig::Credentials::ProviderFields.store('openai', { 'base_url' => 'https://new.test' }, path: path)

        assert_equal 'openai/o3', JSON.parse(File.read(path))['model']
      end
    end

    it 'leaves the file untouched when the fields already match' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'settings.json')
        original = JSON.generate({ 'providers' => { 'openai' => { 'base_url' => 'https://same.test' } } })
        File.write(path, original)

        Riffer::Rig::Credentials::ProviderFields.store('openai', { 'base_url' => 'https://same.test' }, path: path)

        assert_equal original, File.read(path)
      end
    end
  end

  describe '.remove' do
    it 'writes nothing when the provider has no block' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'settings.json')

        Riffer::Rig::Credentials::ProviderFields.remove('openai', path: path)

        refute_path_exists path
      end
    end

    it 'keeps the other blocks' do
      Dir.mktmpdir do |dir|
        path = settings_file(
          dir,
          { 'providers' => { 'openai' => { 'base_url' => 'https://proxy.test' },
                             'amazon_bedrock' => { 'region' => 'us-west-2' } } }
        )

        Riffer::Rig::Credentials::ProviderFields.remove('openai', path: path)

        assert_equal({ 'amazon_bedrock' => { 'region' => 'us-west-2' } }, JSON.parse(File.read(path))['providers'])
      end
    end

    it 'drops the providers key when the last block goes' do
      Dir.mktmpdir do |dir|
        path = settings_file(
          dir,
          { 'model' => 'openai/o3', 'providers' => { 'openai' => { 'base_url' => 'https://proxy.test' } } }
        )

        Riffer::Rig::Credentials::ProviderFields.remove('openai', path: path)

        refute_includes JSON.parse(File.read(path)), 'providers'
      end
    end
  end
end
