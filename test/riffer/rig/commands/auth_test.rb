# frozen_string_literal: true

require 'test_helper'
require 'forwardable'
require 'fileutils'
require 'json'
class AcmeAuthProvider < Riffer::Providers::Mock; end # rubocop:disable Rig/NoInheritance -- riffer builds providers through Riffer::Providers::Base subclasses

class AnsweringAuthHost
  extend Forwardable

  def_delegators :@null, :capabilities, :confirm, :notify, :progress

  attr_reader :asked

  def initialize(answer)
    @null = Riffer::Rig::Hosts::Null.new
    @answer = answer
    @asked = []
  end

  def ask(question = nil, options: nil, secret: false)
    @asked << { question: question, secret: secret }
    @answer
  end
end

describe Riffer::Rig::Commands::Auth do
  def secret_env_vars
    %w[
      ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY OPENROUTER_API_KEY
      AZURE_OPENAI_API_KEY AWS_BEARER_TOKEN_BEDROCK
    ]
  end

  before do
    @saved_env = secret_env_vars.to_h { |name| [name, ENV.fetch(name, nil)] }
    secret_env_vars.each { |name| ENV[name] = nil }
    FileUtils.rm_f(Riffer::Rig::Credentials::PATH)
    FileUtils.rm_f(Riffer::Rig::Settings::PATH)
  end

  after do
    @saved_env.each { |name, value| ENV[name] = value }
    FileUtils.rm_f(Riffer::Rig::Credentials::PATH)
    FileUtils.rm_f(Riffer::Rig::Settings::PATH)
  end

  def command_events(runtime, args)
    events = []
    runtime.run_command('auth', args) { |event| events << event }
    events
  end

  def output(text)
    Riffer::Rig::Events::CommandOutput.new('auth', text)
  end

  it 'is listed in the Runtime commands' do
    assert_includes Riffer::Rig::Runtime.new('mock/test').commands.map(&:name), 'auth'
  end

  describe 'listing' do
    it 'reports each provider with its status' do
      ENV['ANTHROPIC_API_KEY'] = 'sk-env'
      Riffer::Rig::Credentials.store(:openai, { api_key: 'sk-stored' })

      assert_equal(
        [output(<<~TABLE.chomp)],
          amazon_bedrock  chain
          anthropic       env
          azure_openai    missing
          gemini          missing
          openai          stored
          openrouter      missing
        TABLE
        command_events(Riffer::Rig::Runtime.new('mock/test'), '')
      )
    end
  end

  describe 're-running a provider' do
    before do
      @api_key = Riffer.config.anthropic.api_key
    end

    after do
      Riffer.config.anthropic.api_key = @api_key
    end

    it 'stores the key the host answers' do
      host = AnsweringAuthHost.new('sk-new')
      runtime = Riffer::Rig::Runtime.new('mock/test', host: host)
      command_events(runtime, 'anthropic')

      assert_equal 'sk-new', Riffer::Rig::Credentials.resolve(:anthropic, host: host).values[:api_key]
    end

    it 'applies the new key to the provider config' do
      runtime = Riffer::Rig::Runtime.new('mock/test', host: AnsweringAuthHost.new('sk-new'))
      command_events(runtime, 'anthropic')

      assert_equal 'sk-new', Riffer.config.anthropic.api_key
    end

    it 'updates the Runtime credentials' do
      runtime = Riffer::Rig::Runtime.new('mock/test', host: AnsweringAuthHost.new('sk-new'))
      command_events(runtime, 'anthropic')

      assert_equal({ api_key: 'sk-new' }, runtime.credentials[:anthropic])
    end

    it 'reports the update' do
      runtime = Riffer::Rig::Runtime.new('mock/test', host: AnsweringAuthHost.new('sk-new'))

      assert_equal [output('Updated anthropic credentials')], command_events(runtime, 'anthropic')
    end

    it 'asks for the required field with hidden input' do
      host = AnsweringAuthHost.new('sk-new')
      runtime = Riffer::Rig::Runtime.new('mock/test', host: host)
      command_events(runtime, 'anthropic')

      assert_equal [{ question: 'anthropic api_key', secret: true }], host.asked
    end

    it 'refuses through notify when the host declines' do
      runtime = Riffer::Rig::Runtime.new('mock/test')

      assert_equal(
        [Riffer::Rig::Events::Notify.new('anthropic still has no api_key (ANTHROPIC_API_KEY)', :error)],
        command_events(runtime, 'anthropic')
      )
    end

    it 'rejects an unknown provider with the providers in the hint' do
      runtime = Riffer::Rig::Runtime.new('mock/test')

      assert_equal(
        [output(
          'Use /auth <provider> or /auth remove <provider>, with a provider from: ' \
          'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter'
        )],
        command_events(runtime, 'acme')
      )
    end
  end

  describe 'removing a provider' do
    it 'deletes the auth.json entry' do
      Riffer::Rig::Credentials.store(:openai, { api_key: 'sk-openai' })
      runtime = Riffer::Rig::Runtime.new('mock/test')
      command_events(runtime, 'remove openai')

      assert_empty JSON.parse(File.read(Riffer::Rig::Credentials::PATH))
    end

    it 'deletes the providers block in settings' do
      Riffer::Rig::Credentials.store(:openai, { api_key: 'sk-openai', base_url: 'https://proxy.test' })
      runtime = Riffer::Rig::Runtime.new('mock/test')
      command_events(runtime, 'remove openai')

      assert_nil JSON.parse(File.read(Riffer::Rig::Settings::PATH))['providers']
    end

    it 'reports the removal' do
      runtime = Riffer::Rig::Runtime.new('mock/test')

      assert_equal [output('Removed stored openai credentials')], command_events(runtime, 'remove openai')
    end

    it 'rejects an unknown provider with the providers in the hint' do
      runtime = Riffer::Rig::Runtime.new('mock/test')

      assert_equal(
        [output(
          'Use /auth <provider> or /auth remove <provider>, with a provider from: ' \
          'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter'
        )],
        command_events(runtime, 'remove acme')
      )
    end
  end

  describe 'malformed arguments' do
    it 'prints the usage' do
      assert_equal [output('Use /auth, /auth <provider> or /auth remove <provider>')],
                   command_events(Riffer::Rig::Runtime.new('mock/test'), 'anthropic extra')
    end

    it 'prints the hint for a bare remove' do
      assert_equal(
        [output(
          'Use /auth <provider> or /auth remove <provider>, with a provider from: ' \
          'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter'
        )],
        command_events(Riffer::Rig::Runtime.new('mock/test'), 'remove')
      )
    end
  end

  describe 'with a registered extension provider' do
    before do
      @saved = ENV.fetch('ACME_API_KEY', nil)
      ENV['ACME_API_KEY'] = nil
      Riffer::Rig::Registrar.new('acme').provider(:acme) { AcmeAuthProvider }
    end

    after do
      ENV['ACME_API_KEY'] = @saved
      Riffer::Rig::Providers.unregister(:acme)
    end

    it 'lists the registered provider with its status' do
      text = command_events(Riffer::Rig::Runtime.new('mock/test'), '').first.text

      assert_match(/^acme\s+missing$/, text)
    end

    it 'names the registered provider in the hint' do
      text = command_events(Riffer::Rig::Runtime.new('mock/test'), 'remove bogus').first.text

      assert_match(/with a provider from: .*acme/, text)
    end
  end
end
