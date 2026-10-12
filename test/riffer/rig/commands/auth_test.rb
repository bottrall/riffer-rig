# frozen_string_literal: true

require 'test_helper'
require 'forwardable'
require 'fileutils'
class AcmeAuthProvider < Riffer::Providers::Mock; end # rubocop:disable Rig/NoInheritance -- riffer builds providers through Riffer::Providers::Base subclasses

class AnsweringAuthHost
  extend Forwardable

  def_delegators :@null, :confirm, :notify, :progress

  def initialize(answer)
    @null = Riffer::Rig::Hosts::Null.new
    @answer = answer
  end

  def capabilities
    Set[:ask]
  end

  def ask(_question = nil, options: nil, secret: false)
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
    FileUtils.rm_f(Riffer::Rig::Settings::File::PATH)
  end

  after do
    @saved_env.each { |name, value| ENV[name] = value }
    FileUtils.rm_f(Riffer::Rig::Credentials::PATH)
    FileUtils.rm_f(Riffer::Rig::Settings::File::PATH)
  end

  def command_events(runtime, args)
    events = []
    runtime.run_command('auth', args) { |event| events << event }
    events
  end

  def output(text)
    Riffer::Rig::Events::CommandOutput.new('auth', text)
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

    it 'refuses through notify when the host declines' do
      runtime = Riffer::Rig::Runtime.new('mock/test')

      assert_equal(
        [Riffer::Rig::Events::Notify.new('anthropic still has no api_key (ANTHROPIC_API_KEY)', :error)],
        command_events(runtime, 'anthropic')
      )
    end

    it 'does not merge credentials into the Runtime when the host declines' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      command_events(runtime, 'anthropic')

      assert_empty runtime.credentials
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
  end

  describe 'removing a provider' do
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

    it 'reports the removal' do
      runtime = Riffer::Rig::Runtime.new('mock/test')

      assert_equal [output('Removed stored openai credentials')], command_events(runtime, 'remove openai')
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
