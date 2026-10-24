# frozen_string_literal: true

require 'test_helper'
require 'forwardable'
require 'json'
class AcmeCredentialProvider < Riffer::Providers::Mock; end # rubocop:disable Rig/NoInheritance -- riffer builds providers through Riffer::Providers::Base subclasses

class AnsweringHost
  extend Forwardable

  def_delegators :@null, :confirm, :notify, :progress

  attr_reader :asked

  def initialize(answer, &while_asked)
    @null = Riffer::Rig::Hosts::Null.new
    @answer = answer
    @while_asked = while_asked
    @asked = []
  end

  def capabilities
    Set[:ask]
  end

  def ask(question = nil, options: nil, secret: false)
    @asked << { question: question, secret: secret }
    @while_asked&.call
    @answer
  end
end

describe Riffer::Rig::Credentials do
  let(:null_host) { Riffer::Rig::Hosts::Null.new }

  let(:fallback_setup) do
    region = Riffer::Rig::ProviderSetup::Field.new(
      name: :region, env: ['ACME_REGION'], secret: false, required: true, fallback: -> { 'from-fallback' }
    )
    Riffer::Rig::ProviderSetup.new(fields: [region])
  end

  let(:region_setup) do
    region = Riffer::Rig::ProviderSetup::Field.new(name: :region, env: ['ACME_REGION'], secret: false, required: true)
    Riffer::Rig::ProviderSetup.new(fields: [region])
  end

  describe '.install' do
    it 'reports a malformed auth.json' do
      in_tmp_home do |paths|
        malform(paths[:auth_path])

        assert_equal(
          malformed(paths[:auth_path]),
          Riffer::Rig::Credentials.install(:anthropic, host: null_host, env:, config: nil, **paths)
        )
      end
    end

    it 'reports a malformed settings file' do
      in_tmp_home do |paths|
        malform(paths[:settings_path])

        assert_equal(
          malformed(paths[:settings_path]),
          Riffer::Rig::Credentials.install(:anthropic, host: null_host, env:, config: nil, **paths)
        )
      end
    end

    it 'prefers the env var over the stored value' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-stored' }, **paths)

        resolution = Riffer::Rig::Credentials.install(
          :anthropic,
          host: null_host,
          env: env('ANTHROPIC_API_KEY' => 'sk-env'),
          config: nil,
          **paths
        )

        assert_equal({ api_key: 'sk-env' }, resolution.values)
      end
    end

    it 'resolves a stored secret' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-stored' }, **paths)

        resolution = Riffer::Rig::Credentials.install(:anthropic, host: null_host, env:, config: nil, **paths)

        assert_equal({ api_key: 'sk-stored' }, resolution.values)
      end
    end

    it 'never runs a !command found in settings' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: '!echo https://azure.test' }, **paths)

        resolution = Riffer::Rig::Credentials.install(:azure_openai, host: null_host, env:, config: nil, **paths)

        assert_equal '!echo https://azure.test', resolution.values[:endpoint]
      end
    end

    it 'does not run a stored !command when the environment already answers' do
      in_tmp_home do |paths|
        marker = File.join(File.dirname(paths[:auth_path]), 'marker')
        Riffer::Rig::Credentials.store(:anthropic, { api_key: "!touch #{marker}" }, **paths)

        Riffer::Rig::Credentials.install(
          :anthropic,
          host: null_host,
          env: env('ANTHROPIC_API_KEY' => 'sk-env'),
          config: nil,
          **paths
        )

        refute_path_exists marker
      end
    end

    it 'prefers the stored value over the fallback' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:acme, { region: 'from-settings' }, setup: fallback_setup, **paths)

        resolution = Riffer::Rig::Credentials.install(
          :acme,
          host: null_host,
          setup: fallback_setup,
          env:,
          config: nil,
          **paths
        )

        assert_equal({ region: 'from-settings' }, resolution.values)
      end
    end

    it 'prefers the fallback over asking' do
      in_tmp_home do |paths|
        host = AnsweringHost.new('from-host')

        Riffer::Rig::Credentials.install(:acme, host: host, setup: fallback_setup, env:, config: nil, **paths)

        assert_empty host.asked
      end
    end

    it 'returns the fallback value' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.install(
          :acme,
          host: null_host,
          setup: fallback_setup,
          env:,
          config: nil,
          **paths
        )

        assert_equal({ region: 'from-fallback' }, resolution.values)
      end
    end

    it 'does not ask a host that cannot ask' do
      in_tmp_home do |paths|
        host = AnsweringHost.new('sk-asked')
        host.define_singleton_method(:capabilities) { Set[:confirm] }
        Riffer::Rig::Credentials.install(:anthropic, host: host, env:, config: nil, **paths)

        assert_empty host.asked
      end
    end

    it 'asks the host when nothing else resolves' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.install(
          :anthropic,
          host: AnsweringHost.new("sk-asked\n"),
          env:,
          config: nil,
          **paths
        )

        assert_equal({ api_key: 'sk-asked' }, resolution.values)
      end
    end

    it 'treats a blank answer as missing' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.install(
          :anthropic,
          host: AnsweringHost.new(' '),
          env:,
          config: nil,
          **paths
        )

        assert_equal [:api_key], resolution.missing
      end
    end

    it 'asks for a secret field with secret: true' do
      in_tmp_home do |paths|
        host = AnsweringHost.new('sk-asked')

        Riffer::Rig::Credentials.install(:anthropic, host: host, env:, config: nil, **paths)

        assert_equal [{ question: 'anthropic api_key', secret: true }], host.asked
      end
    end

    it 'stores what the host answered' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.install(:anthropic, host: AnsweringHost.new('sk-asked'), env:, config: nil, **paths)

        assert_equal :stored, Riffer::Rig::Credentials.status(:anthropic, env:, auth_path: paths[:auth_path])
      end
    end

    it 'reports an auth.json that turned malformed while the host was asked' do
      in_tmp_home do |paths|
        host = AnsweringHost.new('sk-asked') { malform(paths[:auth_path]) }

        assert_equal(
          malformed(paths[:auth_path]),
          Riffer::Rig::Credentials.install(:anthropic, host: host, env:, config: nil, **paths)
        )
      end
    end

    it 'does not ask again once the answer is stored' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.install(:anthropic, host: AnsweringHost.new('sk-asked'), env:, config: nil, **paths)
        host = AnsweringHost.new('sk-again')

        Riffer::Rig::Credentials.install(:anthropic, host: host, env:, config: nil, **paths)

        assert_empty host.asked
      end
    end

    it 'does not ask for optional fields' do
      in_tmp_home do |paths|
        host = AnsweringHost.new('sk-asked')

        Riffer::Rig::Credentials.install(:openai, host: host, env:, config: nil, **paths)

        assert_equal(['openai api_key'], host.asked.map { |ask| ask[:question] })
      end
    end

    it 'resolves an optional field from settings' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:openai, { base_url: 'https://proxy.test/v1' }, **paths)

        resolution = Riffer::Rig::Credentials.install(:openai, host: null_host, env:, config: nil, **paths)

        assert_equal 'https://proxy.test/v1', resolution.values[:base_url]
      end
    end

    it 'returns what it has when the null host declines' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.install(
          :azure_openai,
          host: null_host,
          env: env('AZURE_OPENAI_ENDPOINT' => 'https://azure.test'),
          config: nil,
          **paths
        )

        assert_equal({ endpoint: 'https://azure.test' }, resolution.values)
      end
    end

    it 'lists the required fields still missing when the null host declines' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.install(
          :azure_openai,
          host: null_host,
          env: env('AZURE_OPENAI_ENDPOINT' => 'https://azure.test'),
          config: nil,
          **paths
        )

        assert_equal [:api_key], resolution.missing
      end
    end

    it 'leaves an optional field out of the missing list' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.install(:openai, host: null_host, env:, config: nil, **paths)

        assert_equal [:api_key], resolution.missing
      end
    end

    it 'returns the resolved values when nothing is missing' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.install(
          :anthropic, host: null_host, env: env('ANTHROPIC_API_KEY' => 'sk-env'), config: Riffer::Config.new, **paths
        )

        assert_equal({ api_key: 'sk-env' }, resolution.values)
      end
    end

    it 'returns the resolution when a required field is missing' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.install(:anthropic, host: null_host, env:, **paths)

        assert_equal [:api_key], resolution.missing
      end
    end

    it 'succeeds when the missing fields are already known' do
      in_tmp_home do |paths|
        resolution = Riffer::Rig::Credentials.install(
          :anthropic, host: null_host, env:, known: { api_key: 'sk-known' }, **paths
        )

        assert_empty resolution.missing
      end
    end

    it 'applies the values to the given config on success' do
      in_tmp_home do |paths|
        config = Riffer::Config.new
        Riffer::Rig::Credentials.install(
          :anthropic, host: null_host, env: env('ANTHROPIC_API_KEY' => 'sk-env'), config: config, **paths
        )

        assert_equal 'sk-env', config.anthropic.api_key
      end
    end

    describe 'without a config argument' do
      before do
        @api_key = Riffer.config.anthropic.api_key
      end

      after do
        Riffer.config.anthropic.api_key = @api_key
      end

      it 'applies the values to Riffer.config' do
        in_tmp_home do |paths|
          Riffer::Rig::Credentials.install(:anthropic, host: AnsweringHost.new('sk-asked'), env:, **paths)

          assert_equal 'sk-asked', Riffer.config.anthropic.api_key
        end
      end
    end

    it 'does not apply when there is no config' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.apply(:anthropic, { api_key: 'sk-old' }, config: Riffer::Config.new)
        Riffer::Rig::Credentials.install(
          :anthropic, host: null_host, env: env('ANTHROPIC_API_KEY' => 'sk-env'), config: nil, **paths
        )

        assert_equal({ api_key: 'sk-old' }, Riffer::Rig::Credentials.read(:anthropic))
      end
    end

    it 'does not apply when a required field is missing' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.apply(:anthropic, { api_key: 'sk-old' }, config: Riffer::Config.new)
        Riffer::Rig::Credentials.install(:anthropic, host: null_host, env:, config: Riffer::Config.new, **paths)

        assert_equal({ api_key: 'sk-old' }, Riffer::Rig::Credentials.read(:anthropic))
      end
    end
  end

  describe '.install_values' do
    it 'reports a malformed auth.json' do
      in_tmp_home do |paths|
        malform(paths[:auth_path])

        assert_equal(
          malformed(paths[:auth_path]),
          Riffer::Rig::Credentials.install_values(:gemini, host: null_host, env:, config: Riffer::Config.new, **paths)
        )
      end
    end

    it 'returns the values when nothing is missing' do
      in_tmp_home do |paths|
        values = Riffer::Rig::Credentials.install_values(
          :gemini, host: null_host, env: env('GEMINI_API_KEY' => 'sk-env'), config: Riffer::Config.new, **paths
        )

        assert_equal({ api_key: 'sk-env' }, values)
      end
    end

    it 'names the missing fields and where to create them' do
      in_tmp_home do |paths|
        assert_equal(
          'gemini has no api_key (GEMINI_API_KEY); set it in the environment or run riffer interactively ' \
          'to paste it (create one at https://aistudio.google.com/app/apikey)',
          Riffer::Rig::Credentials.install_values(:gemini, host: null_host, env:, config: Riffer::Config.new, **paths)
        )
      end
    end

    it 'names the missing fields under the label it is given, without a link when the setup has none' do
      in_tmp_home do |paths|
        assert_equal(
          'MCP server docs has no region (ACME_REGION); set it in the environment or run riffer interactively ' \
          'to paste it',
          Riffer::Rig::Credentials.install_values(
            'docs', host: null_host, env:, label: 'MCP server docs', setup: region_setup, config: nil, **paths
          )
        )
      end
    end
  end

  describe '.apply' do
    let(:config) { Riffer::Config.new }

    describe 'with a registered extension provider' do
      before do
        Riffer::Rig::Providers.register(
          :acme,
          setup: { fields: [{ name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true }] }
        ) { AcmeCredentialProvider }
      end

      after do
        Riffer::Rig::Providers.unregister(:acme)
      end

      it 'keeps the values it receives' do
        Riffer::Rig::Credentials.apply(:acme, { api_key: 'sk-acme' }, config: config)

        assert_equal({ api_key: 'sk-acme' }, Riffer::Rig::Credentials.read(:acme))
      end

      it 'keeps the values of the latest apply' do
        Riffer::Rig::Credentials.apply(:acme, { api_key: 'sk-earlier' }, config: config)
        Riffer::Rig::Credentials.apply(:acme, { api_key: 'sk-later' }, config: config)

        assert_equal({ api_key: 'sk-later' }, Riffer::Rig::Credentials.read(:acme))
      end

      it 'freezes the values it keeps' do
        Riffer::Rig::Credentials.apply(:acme, { api_key: 'sk-acme' }, config: config)

        assert_predicate Riffer::Rig::Credentials.read(:acme), :frozen?
      end

      it 'assigns nothing to the riffer config for a registered extension provider' do
        Riffer::Rig::Credentials.apply(:acme, { api_key: 'sk-acme' }, config: config)

        refute_respond_to config, :acme
      end
    end

    it 'assigns nothing for a provider without a built-in setup' do
      assert_nil Riffer::Rig::Credentials.apply(:acme, { api_key: 'sk-acme' }, config: config)
    end

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
  end

  describe '.read' do
    it 'reads nil before anything is applied for a provider' do
      assert_nil Riffer::Rig::Credentials.read(:untouched)
    end
  end

  describe '.store' do
    it 'reports a malformed auth.json' do
      in_tmp_home do |paths|
        malform(paths[:auth_path])

        assert_equal(
          malformed(paths[:auth_path]),
          Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-stored' }, **paths)
        )
      end
    end

    it 'leaves settings unwritten when auth.json is malformed' do
      in_tmp_home do |paths|
        malform(paths[:auth_path])
        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: 'https://azure.test', api_key: 'azure-key' }, **paths)

        refute_path_exists paths[:settings_path]
      end
    end

    it 'reports a malformed settings file' do
      in_tmp_home do |paths|
        malform(paths[:settings_path])

        assert_equal(
          malformed(paths[:settings_path]),
          Riffer::Rig::Credentials.store(:openai, { base_url: 'https://proxy.test/v1' }, **paths)
        )
      end
    end

    it 'leaves auth.json unwritten when the settings file is malformed' do
      in_tmp_home do |paths|
        malform(paths[:settings_path])
        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: 'https://azure.test', api_key: 'azure-key' }, **paths)

        refute_path_exists paths[:auth_path]
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

    it 'keeps non-secret fields out of auth.json' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: 'https://azure.test', api_key: 'azure-key' }, **paths)

        assert_equal(
          { 'type' => 'api_key', 'api_key' => 'azure-key' },
          JSON.parse(File.read(paths[:auth_path]))['azure_openai']
        )
      end
    end

    it 'leaves auth.json unwritten when no field is secret' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: 'https://azure.test' }, **paths)

        refute_path_exists paths[:auth_path]
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

    it 'leaves settings unwritten when every field is secret' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-ant' }, **paths)

        refute_path_exists paths[:settings_path]
      end
    end
  end

  describe '.remove' do
    it 'reports a malformed auth.json' do
      in_tmp_home do |paths|
        malform(paths[:auth_path])

        assert_equal(malformed(paths[:auth_path]), Riffer::Rig::Credentials.remove(:anthropic, **paths))
      end
    end

    it 'keeps the providers block when auth.json is malformed' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:openai, { base_url: 'https://proxy.test/v1' }, **paths)
        malform(paths[:auth_path])
        Riffer::Rig::Credentials.remove(:openai, **paths)

        assert_includes JSON.parse(File.read(paths[:settings_path])), 'providers'
      end
    end

    it 'reports a malformed settings file' do
      in_tmp_home do |paths|
        malform(paths[:settings_path])

        assert_equal(malformed(paths[:settings_path]), Riffer::Rig::Credentials.remove(:anthropic, **paths))
      end
    end

    it 'keeps the auth.json entry when the settings file is malformed' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-stored' }, **paths)
        malform(paths[:settings_path])
        Riffer::Rig::Credentials.remove(:anthropic, **paths)

        assert_includes JSON.parse(File.read(paths[:auth_path])), 'anthropic'
      end
    end

    it 'leaves auth.json unwritten when the provider has no entry' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.remove(:anthropic, **paths)

        refute_path_exists paths[:auth_path]
      end
    end

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

    describe 'without path arguments' do
      before do
        Riffer::Rig::Credentials.store(:azure_openai, { endpoint: 'https://azure.test', api_key: 'azure-key' })
        Riffer::Rig::Credentials.remove(:azure_openai)
      end

      after do
        FileUtils.rm_f(Riffer::Rig::Credentials::PATH)
        FileUtils.rm_f(Riffer::Rig::Settings::File::PATH)
      end

      it 'deletes the entry from the default auth.json' do
        refute_includes JSON.parse(File.read(Riffer::Rig::Credentials::PATH)), 'azure_openai'
      end

      it 'deletes the providers block from the default settings file' do
        refute_includes JSON.parse(File.read(Riffer::Rig::Settings::File::PATH)), 'providers'
      end
    end
  end

  describe '.status' do
    it 'is :env when the secret comes from the environment' do
      in_tmp_home do |paths|
        status = Riffer::Rig::Credentials.status(
          :anthropic,
          env: env('ANTHROPIC_API_KEY' => 'sk-env'),
          auth_path: paths[:auth_path]
        )

        assert_equal :env, status
      end
    end

    it 'reports a malformed auth.json' do
      in_tmp_home do |paths|
        malform(paths[:auth_path])

        assert_equal(
          malformed(paths[:auth_path]),
          Riffer::Rig::Credentials.status(:anthropic, env:, auth_path: paths[:auth_path])
        )
      end
    end

    it 'is :stored when the secret is in auth.json' do
      in_tmp_home do |paths|
        Riffer::Rig::Credentials.store(:anthropic, { api_key: 'sk-stored' }, **paths)

        assert_equal :stored, Riffer::Rig::Credentials.status(:anthropic, env:, auth_path: paths[:auth_path])
      end
    end

    it 'is :chain for a chain setup with no secret' do
      in_tmp_home do |paths|
        assert_equal :chain, Riffer::Rig::Credentials.status(:amazon_bedrock, env:, auth_path: paths[:auth_path])
      end
    end

    it 'is :missing otherwise' do
      in_tmp_home do |paths|
        assert_equal :missing, Riffer::Rig::Credentials.status(:anthropic, env:, auth_path: paths[:auth_path])
      end
    end
  end

  private

  def env(vars = {})
    Riffer::Rig::Env.new(vars)
  end

  def malform(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, '{"openai":{"a":1},}')
  end

  def malformed(path)
    "#{path} is not valid JSON at line 1 column 19"
  end

  def in_tmp_home
    Dir.mktmpdir do |dir|
      yield({ auth_path: File.join(dir, '.riffer', 'auth.json'),
              settings_path: File.join(dir, '.riffer', 'settings.json') })
    end
  end
end
