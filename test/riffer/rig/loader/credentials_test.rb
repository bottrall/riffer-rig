# frozen_string_literal: true

require 'test_helper'
require 'json'
require_relative '../../../support/confirming_host'

describe Riffer::Rig::Loader::Credentials do
  before do
    @home = Dir.mktmpdir
    @config = Riffer::Config.new
  end

  after do
    FileUtils.remove_entry(@home)
  end

  def auth_path
    File.join(@home, '.riffer', 'auth.json')
  end

  def install(provider: 'gemini', host: Riffer::Rig::Hosts::Null.new, env: {})
    Riffer::Rig::Loader::Credentials.install(
      provider,
      host: host,
      env: Riffer::Rig::Env.new(env),
      config: @config,
      auth_path: auth_path,
      settings_path: File.join(@home, '.riffer', 'settings.json')
    )
  end

  describe '.install' do
    it 'reports a malformed auth.json' do
      FileUtils.mkdir_p(File.dirname(auth_path))
      File.write(auth_path, '{"gemini":{"a":1},}')

      assert_equal "#{auth_path} is not valid JSON at line 1 column 19", install
    end

    it 'returns the values resolved from the environment' do
      assert_equal({ api_key: 'sk-gem-env' }, install(env: { 'GEMINI_API_KEY' => 'sk-gem-env' }))
    end

    it 'assigns the resolved values to the riffer config' do
      install(env: { 'GEMINI_API_KEY' => 'sk-gem-env' })

      assert_equal 'sk-gem-env', @config.gemini.api_key
    end

    describe 'with a provider an extension registered' do
      after do
        Riffer::Rig::Providers.unregister(:acme)
      end

      it 'resolves the field of its setup from the env var the setup names' do
        Riffer::Rig::Providers.register(
          :acme,
          setup: { fields: [{ name: :api_key, env: ['ACME_SECRET'], secret: true, required: true }] }
        ) { Riffer::Providers::Mock }

        assert_equal({ api_key: 'sk-acme' }, install(provider: 'acme', env: { 'ACME_SECRET' => 'sk-acme' }))
      end

      it 'resolves a setup-less registration through the generic fallback' do
        Riffer::Rig::Providers.register(:acme) { Riffer::Providers::Mock }

        assert_equal({ api_key: 'sk-acme' }, install(provider: 'acme', env: { 'ACME_API_KEY' => 'sk-acme' }))
      end
    end

    it 'reads a key stored at the auth path' do
      FileUtils.mkdir_p(File.dirname(auth_path))
      File.write(auth_path, JSON.generate({ gemini: { type: 'api_key', api_key: 'sk-gem-stored' } }))

      assert_equal({ api_key: 'sk-gem-stored' }, install)
    end

    it 'asks a host that can ask for a missing key' do
      assert_equal({ api_key: 'sk-gem-pasted' }, install(host: ConfirmingHost.new(['sk-gem-pasted'])))
    end

    it 'reports a key the host cannot supply as a message naming it' do
      assert_equal(
        'gemini has no api_key (GEMINI_API_KEY); set it in the environment or run riffer interactively ' \
        'to paste it (create one at https://aistudio.google.com/app/apikey)',
        install
      )
    end

    it 'omits the console link when the provider has none' do
      assert_equal(
        'mystery has no api_key (MYSTERY_API_KEY); set it in the environment or run riffer interactively ' \
        'to paste it',
        install(provider: 'mystery')
      )
    end
  end
end
