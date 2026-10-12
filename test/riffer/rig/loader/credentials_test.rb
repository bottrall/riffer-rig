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

  def install(host: Riffer::Rig::Hosts::Null.new, env: {})
    Riffer::Rig::Loader::Credentials.install(
      'gemini',
      host: host,
      env: Riffer::Rig::Env.new(env),
      config: @config,
      auth_path: auth_path,
      settings_path: File.join(@home, '.riffer', 'settings.json')
    )
  end

  describe '.install' do
    it 'returns the values resolved from the environment' do
      assert_equal({ api_key: 'sk-gem-env' }, install(env: { 'GEMINI_API_KEY' => 'sk-gem-env' }))
    end

    it 'assigns the resolved values to the riffer config' do
      install(env: { 'GEMINI_API_KEY' => 'sk-gem-env' })

      assert_equal 'sk-gem-env', @config.gemini.api_key
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

    it 'leaves the riffer config alone when a key is missing' do
      install

      assert_nil @config.gemini.api_key
    end
  end
end
