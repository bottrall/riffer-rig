# frozen_string_literal: true

require 'test_helper'
require 'json'

class AnsweringHost < Riffer::Rig::Hosts::Null
  attr_reader :asked

  def initialize(answer)
    super()
    @answer = answer
    @asked = []
  end

  def ask(question = nil, options: nil, secret: false)
    @asked << { question: question, secret: secret }
    @answer
  end
end

describe Riffer::Rig::Credentials do
  let(:null_host) { Riffer::Rig::Hosts::Null.new }

  let(:fallback_recipe) do
    fallback = -> { 'from-fallback' }
    { fields: [{ name: :region, env: ['ACME_REGION'], secret: false, required: true, fallback: fallback }] }
  end

  describe '.resolve' do
    it 'prefers the env var over the stored value' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-stored' }, **paths)

        resolution = Riffer::Rig::Credentials.resolve(
          :anthropic,
          host: null_host,
          env: { 'ANTHROPIC_API_KEY' => 'sk-env' },
          **paths
        )

        assert_equal({ api_key: 'sk-env' }, resolution.values)
      end
    end

    it 'reads a later env var when the first is unset' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.resolve(
          :amazon_bedrock,
          host: null_host,
          env: { 'AWS_DEFAULT_REGION' => 'us-west-2' },
          **paths
        )

        assert_equal 'us-west-2', resolution.values[:region]
      end
    end

    it 'treats a blank env var as unset' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.resolve(
          :anthropic,
          host: null_host,
          env: { 'ANTHROPIC_API_KEY' => ' ' },
          **paths
        )

        assert_equal [:api_key], resolution.missing
      end
    end

    it 'prefers the stored value over the fallback' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:acme, { region: 'from-settings' }, recipe: fallback_recipe, **paths)

        resolution = Riffer::Rig::Credentials.resolve(:acme, host: null_host, recipe: fallback_recipe, env: {}, **paths)

        assert_equal({ region: 'from-settings' }, resolution.values)
      end
    end

    it 'prefers the fallback over asking' do
      in_tmp_home do |paths|
        host = AnsweringHost.new('from-host')

        Riffer::Rig::Credentials.resolve(:acme, host: host, recipe: fallback_recipe, env: {}, **paths)

        assert_empty host.asked
      end
    end

    it 'returns the fallback value' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.resolve(:acme, host: null_host, recipe: fallback_recipe, env: {}, **paths)

        assert_equal({ region: 'from-fallback' }, resolution.values)
      end
    end

    it 'asks the host when nothing else resolves' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.resolve(
          :anthropic,
          host: AnsweringHost.new("sk-asked\n"),
          env: {},
          **paths
        )

        assert_equal({ api_key: 'sk-asked' }, resolution.values)
      end
    end

    it 'asks for a secret field with secret: true' do
      in_tmp_home do |paths|
        host = AnsweringHost.new('sk-asked')

        Riffer::Rig::Credentials.resolve(:anthropic, host: host, env: {}, **paths)

        assert_equal [{ question: 'anthropic api_key', secret: true }], host.asked
      end
    end

    it 'stores what the host answered' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.resolve(:anthropic, host: AnsweringHost.new('sk-asked'), env: {}, **paths)

        assert_equal :stored, Riffer::Rig::Credentials.status(:anthropic, env: {}, auth_path: paths[:auth_path])
      end
    end

    it 'does not ask for optional fields' do
      in_tmp_home do |paths|
        host = AnsweringHost.new('sk-asked')

        Riffer::Rig::Credentials.resolve(:openai, host: host, env: {}, **paths)

        assert_equal(['openai api_key'], host.asked.map { |ask| ask[:question] })
      end
    end

    it 'resolves an optional field from settings' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:openai, { base_url: 'https://proxy.test/v1' }, **paths)

        resolution = Riffer::Rig::Credentials.resolve(:openai, host: null_host, env: {}, **paths)

        assert_equal 'https://proxy.test/v1', resolution.values[:base_url]
      end
    end

    it 'returns what it has when the null host declines' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.resolve(
          :azure_openai,
          host: null_host,
          env: { 'AZURE_OPENAI_ENDPOINT' => 'https://azure.test' },
          **paths
        )

        assert_equal({ endpoint: 'https://azure.test' }, resolution.values)
      end
    end

    it 'lists the required fields still missing when the null host declines' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.resolve(
          :azure_openai,
          host: null_host,
          env: { 'AZURE_OPENAI_ENDPOINT' => 'https://azure.test' },
          **paths
        )

        assert_equal [:api_key], resolution.missing
      end
    end

    it 'leaves an optional field out of the missing list' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.resolve(:openai, host: null_host, env: {}, **paths)

        assert_equal [:api_key], resolution.missing
      end
    end

    it 'expands a stored $VAR reference' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: '$MY_ANTHROPIC_KEY' }, **paths)

        resolution = Riffer::Rig::Credentials.resolve(
          :anthropic,
          host: null_host,
          env: { 'MY_ANTHROPIC_KEY' => 'sk-referenced' },
          **paths
        )

        assert_equal({ api_key: 'sk-referenced' }, resolution.values)
      end
    end

    it 'expands a stored !command to its stdout' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: '!echo sk-from-command' }, **paths)

        resolution = Riffer::Rig::Credentials.resolve(:anthropic, host: null_host, env: {}, **paths)

        assert_equal({ api_key: 'sk-from-command' }, resolution.values)
      end
    end

    it 'treats a failing !command as missing' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: '!exit 1' }, **paths)

        resolution = Riffer::Rig::Credentials.resolve(:anthropic, host: null_host, env: {}, **paths)

        assert_equal [:api_key], resolution.missing
      end
    end

    it 'never runs a !command found in settings' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: '!echo https://azure.test' }, **paths)

        resolution = Riffer::Rig::Credentials.resolve(:azure_openai, host: null_host, env: {}, **paths)

        assert_equal '!echo https://azure.test', resolution.values[:endpoint]
      end
    end

    it 'ignores the old flat file shape' do
      in_tmp_home do |paths|
        FileUtils.mkdir_p(File.dirname(paths[:auth_path]))
        File.write(paths[:auth_path], JSON.generate('anthropic' => 'sk-ant-flat'))

        resolution = Riffer::Rig::Credentials.resolve(:anthropic, host: null_host, env: {}, **paths)

        assert_empty resolution.values
      end
    end
  end

  describe '.store' do
    it 'writes auth.json owner-only' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-stored' }, **paths)

        assert_equal 0o600, File.stat(paths[:auth_path]).mode & 0o777
      end
    end

    it 'creates the directory owner-only' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-stored' }, **paths)

        assert_equal 0o700, File.stat(File.dirname(paths[:auth_path])).mode & 0o777
      end
    end

    it 'writes a typed entry per provider' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-ant' }, **paths)
        Riffer::Rig::Credentials.store(:amazon_bedrock, { api_token: 'bedrock-token' }, **paths)

        expected = {
          'anthropic' => { 'type' => 'api_key', 'api_key' => 'sk-ant' },
          'amazon_bedrock' => { 'type' => 'api_key', 'api_token' => 'bedrock-token' }
        }

        assert_equal expected, JSON.parse(File.read(paths[:auth_path]))
      end
    end

    it 'writes non-secret fields to the providers block in settings' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: 'https://azure.test', api_key: 'azure-key' }, **paths)

        assert_equal(
          { 'azure_openai' => { 'endpoint' => 'https://azure.test' } },
          JSON.parse(File.read(paths[:settings_path]))['providers']
        )
      end
    end

    it 'keeps non-secret fields out of auth.json' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: 'https://azure.test', api_key: 'azure-key' }, **paths)

        assert_equal(
          { 'type' => 'api_key', 'api_key' => 'azure-key' },
          JSON.parse(File.read(paths[:auth_path]))['azure_openai']
        )
      end
    end

    it 'keeps the other settings keys' do
      in_tmp_home do |paths|
        FileUtils.mkdir_p(File.dirname(paths[:settings_path]))
        File.write(paths[:settings_path], JSON.generate('model' => 'azure_openai/gpt-5'))

        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: 'https://azure.test' }, **paths)

        assert_equal 'azure_openai/gpt-5', JSON.parse(File.read(paths[:settings_path]))['model']
      end
    end
  end

  describe '.remove' do
    it 'deletes the auth.json entry' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: 'https://azure.test', api_key: 'azure-key' }, **paths)

        Riffer::Rig::Credentials.remove(:azure_openai, **paths)

        refute_includes JSON.parse(File.read(paths[:auth_path])), 'azure_openai'
      end
    end

    it 'deletes the providers block in settings' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: 'https://azure.test', api_key: 'azure-key' }, **paths)

        Riffer::Rig::Credentials.remove(:azure_openai, **paths)

        refute_includes JSON.parse(File.read(paths[:settings_path])), 'providers'
      end
    end

    it 'leaves the other providers stored' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-ant' }, **paths)
        Riffer::Rig::Credentials.store(:openai, { api_key: 'sk-oai' }, **paths)

        Riffer::Rig::Credentials.remove(:openai, **paths)

        assert_equal ['anthropic'], JSON.parse(File.read(paths[:auth_path])).keys
      end
    end
  end

  describe '.status' do
    it 'is :env when the secret comes from the environment' do
      in_tmp_home do |paths|
        status = Riffer::Rig::Credentials.status(
          :anthropic,
          env: { 'ANTHROPIC_API_KEY' => 'sk-env' },
          auth_path: paths[:auth_path]
        )

        assert_equal :env, status
      end
    end

    it 'is :stored when the secret is in auth.json' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-stored' }, **paths)

        assert_equal :stored, Riffer::Rig::Credentials.status(:anthropic, env: {}, auth_path: paths[:auth_path])
      end
    end

    it 'is :chain for a chain recipe with no secret' do
      in_tmp_home do |paths|
        assert_equal :chain, Riffer::Rig::Credentials.status(:amazon_bedrock, env: {}, auth_path: paths[:auth_path])
      end
    end

    it 'is :missing otherwise' do
      in_tmp_home do |paths|
        assert_equal :missing, Riffer::Rig::Credentials.status(:anthropic, env: {}, auth_path: paths[:auth_path])
      end
    end
  end

  describe '.apply' do
    let(:config) { Riffer::Config.new }

    it 'assigns api_key to the provider config' do
      Riffer::Rig::Credentials.apply(:anthropic, { api_key: 'sk-ant' }, config: config)

      assert_equal 'sk-ant', config.anthropic.api_key
    end

    it 'assigns the Azure endpoint' do
      Riffer::Rig::Credentials.apply(
        :azure_openai,
        { endpoint: 'https://azure.test', api_key: 'azure-key' },
        config: config
      )

      assert_equal 'https://azure.test', config.azure_openai.endpoint
    end

    it 'assigns the Bedrock region' do
      Riffer::Rig::Credentials.apply('amazon_bedrock', { region: 'us-west-2' }, config: config)

      assert_equal 'us-west-2', config.amazon_bedrock.region
    end

    it 'leaves members with no resolved value untouched' do
      config.amazon_bedrock.api_token = 'already-set'

      Riffer::Rig::Credentials.apply(:amazon_bedrock, { region: 'us-west-2' }, config: config)

      assert_equal 'already-set', config.amazon_bedrock.api_token
    end

    it 'assigns nothing for a provider without a built-in recipe' do
      assert_nil Riffer::Rig::Credentials.apply(:acme, { api_key: 'sk-acme' }, config: config)
    end
  end

  private

  def in_tmp_home
    Dir.mktmpdir do |dir|
      yield({ auth_path: File.join(dir, '.riffer', 'auth.json'),
              settings_path: File.join(dir, '.riffer', 'settings.json') })
    end
  end
end
