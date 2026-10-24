# frozen_string_literal: true

require 'test_helper'
require 'forwardable'
require 'fileutils'
require 'json'
require_relative '../../../support/sdk_fake'
class AcmeModelProvider < Riffer::Providers::Mock; end # rubocop:disable Rig/NoInheritance -- riffer builds providers through Riffer::Providers::Base subclasses

class AnsweringModelHost
  extend Forwardable

  def_delegators :@null, :confirm, :notify, :progress

  attr_reader :asked #: Array[{ question: String?, secret: bool }]

  # @rbs answer: String?
  # @rbs return: void
  def initialize(answer)
    @null = Riffer::Rig::Hosts::Null.new
    @answer = answer
    @asked = []
  end

  # @rbs return: Set[Symbol]
  def capabilities
    Set[:ask]
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question = nil, options: nil, secret: false)
    @asked << { question: question, secret: secret }
    @answer
  end
end

describe Riffer::Rig::Commands::Model do
  def secret_env_vars
    %w[
      ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY OPENROUTER_API_KEY
      AZURE_OPENAI_ENDPOINT AZURE_OPENAI_API_KEY AWS_BEARER_TOKEN_BEDROCK
    ]
  end

  before do
    @saved_env = secret_env_vars.to_h { |name| [name, ENV.fetch(name, nil)] }
    secret_env_vars.each { |name| ENV[name] = nil }
    @saved_keys = { openai: Riffer.config.openai.api_key, gemini: Riffer.config.gemini.api_key }
    @home = Dir.mktmpdir
    @auth_path = File.join(@home, 'auth.json')
    @settings_path = File.join(@home, 'settings.json')
  end

  after do
    @saved_env.each { |name, value| ENV[name] = value }
    @saved_keys.each do |provider, key|
      Riffer.config.public_send(provider).api_key = key
    end
    FileUtils.remove_entry(@home)
  end

  def new_runtime(**)
    Riffer::Rig::Runtime.new('mock/test', auth_path: @auth_path, settings_path: @settings_path, **)
  end

  def command_events(runtime, args)
    events = []
    runtime.run_command('model', args) { |event| events << event }
    events
  end

  def model_events(runtime, args, sdk: SdkFake.new)
    events = []
    ctx = Riffer::Rig::Command::Context.new(
      'model',
      args,
      runtime: runtime,
      host: runtime.host,
      settings: {},
      emit: ->(event) { events << event },
      turn: ->(_text) {}
    )
    Riffer::Rig::Commands::Model.command(
      env: Riffer::Rig::Env.new, auth_path: @auth_path, settings_path: @settings_path, sdk: sdk
    ).call(ctx)
    events + runtime.host.drain
  end

  def output(text)
    Riffer::Rig::Events::CommandOutput.new('model', text)
  end

  def write_home_settings(data)
    FileUtils.mkdir_p(File.dirname(@settings_path))
    File.write(@settings_path, JSON.generate(data))
  end

  def saved_settings
    return {} unless File.file?(@settings_path)

    JSON.parse(File.read(@settings_path))
  end

  def malform(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, '{"reasoning":"low",}')
  end

  def malformed(path)
    Riffer::Rig::Events::Notify.new("#{path} is not valid JSON at line 1 column 20", :error)
  end

  it 'reports the current model without arguments' do
    assert_equal [output('Model: mock/test')], command_events(new_runtime, '')
  end

  describe 'save' do
    it 'saves the current model to the home settings' do
      write_home_settings(model: 'gemini/gem-2.5-pro', reasoning: 'high')
      command_events(new_runtime, '--save')

      assert_equal 'mock/test', saved_settings['model']
    end
  end

  it 'rejects a bare name with the providers in the command output' do
    assert_equal(
      [output(
        'Use /model provider/name, with a provider from: ' \
        'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter'
      )],
      command_events(new_runtime, 'sonnet')
    )
  end

  it 'keeps the model after rejecting a bare name' do
    runtime = new_runtime
    command_events(runtime, 'sonnet')

    assert_equal 'mock/test', runtime.model
  end

  it 'rejects an unknown provider with the providers in the command output' do
    assert_equal(
      [output(
        'Use /model provider/name, with a provider from: ' \
        'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter'
      )],
      command_events(new_runtime, 'acme/fast')
    )
  end

  describe 'sdk' do
    it "ensures the provider's SDK gem" do
      sdk = SdkFake.new
      model_events(new_runtime(credentials: { openai: { api_key: 'stored' } }), 'openai/gpt-5', sdk: sdk)

      assert_equal [['openai', '~> 0.80']], sdk.ensured
    end

    it 'refuses a provider whose SDK gem is missing' do
      runtime = new_runtime(credentials: { openai: { api_key: 'stored' } })

      assert_equal(
        [Riffer::Rig::Events::Notify.new('openai is not installed', :error)],
        model_events(runtime, 'openai/gpt-5', sdk: SdkFake.new('openai is not installed'))
      )
    end

    it 'keeps the model after the SDK refusal' do
      runtime = new_runtime(credentials: { openai: { api_key: 'stored' } })
      model_events(runtime, 'openai/gpt-5', sdk: SdkFake.new('openai is not installed'))

      assert_equal 'mock/test', runtime.model
    end
  end

  describe 'switching to a provider without credentials' do
    it 'does not ask when the Runtime already has the credentials' do
      host = AnsweringModelHost.new('sk-new')
      runtime = new_runtime(host: host, credentials: { gemini: { api_key: 'stored' } })
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_empty host.asked
    end

    it 'asks for the missing field with hidden input' do
      host = AnsweringModelHost.new('sk-new')
      runtime = new_runtime(host: host)
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_equal [{ question: 'gemini api_key', secret: true }], host.asked
    end

    it 'reports a malformed auth.json' do
      malform(@auth_path)

      assert_equal([malformed(@auth_path)], command_events(new_runtime, 'gemini/gem-2.5-pro'))
    end

    it 'keeps the model when auth.json is malformed' do
      malform(@auth_path)
      runtime = new_runtime
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_equal 'mock/test', runtime.model
    end

    it 'refuses with one notify when the host cannot ask' do
      events = command_events(new_runtime, 'gemini/gem-2.5-pro')

      assert_equal(
        [Riffer::Rig::Events::Notify.new(
          'Not switching to gemini/gem-2.5-pro: gemini has no api_key (GEMINI_API_KEY)', :error
        )],
        events
      )
    end

    it 'keeps the model after refusing' do
      runtime = new_runtime
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_equal 'mock/test', runtime.model
    end

    it 'refuses a provider missing one of its required fields' do
      runtime = new_runtime(credentials: { azure_openai: { api_key: 'key' } })
      events = model_events(runtime, 'azure_openai/gpt-5')

      assert_equal 'Not switching to azure_openai/gpt-5: azure_openai has no endpoint (AZURE_OPENAI_ENDPOINT)',
                   events.first.message
    end

    it 'updates the Runtime credentials' do
      runtime = new_runtime(host: AnsweringModelHost.new('sk-new'))
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_equal({ api_key: 'sk-new' }, runtime.credentials[:gemini])
    end

    it 'merges the resolved fields into the Runtime credentials it already holds' do
      ENV['AZURE_OPENAI_ENDPOINT'] = 'https://azure.test'
      runtime = new_runtime(credentials: { azure_openai: { api_key: 'key' } })
      model_events(runtime, 'azure_openai/gpt-5')

      assert_equal({ api_key: 'key', endpoint: 'https://azure.test' }, runtime.credentials[:azure_openai])
    end

    it 'switches the Runtime model' do
      runtime = new_runtime(host: AnsweringModelHost.new('sk-new'))
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_equal 'gemini/gem-2.5-pro', runtime.model
    end

    it 'succeeds when the Runtime already holds part of the required credentials' do
      ENV['AZURE_OPENAI_ENDPOINT'] = 'https://azure.test'
      runtime = new_runtime(credentials: { azure_openai: { api_key: 'key' } })
      model_events(runtime, 'azure_openai/gpt-5')

      assert_equal 'azure_openai/gpt-5', runtime.model
    end
  end

  it 'does not save when the switch is refused' do
    runtime = new_runtime
    command_events(runtime, 'openai/gpt-5 --save')

    assert_nil saved_settings['model']
  end

  it 'switches the Runtime model' do
    runtime = new_runtime
    command_events(runtime, 'mock/other')

    assert_equal 'mock/other', runtime.model
  end

  it 'saves a new model after switching' do
    runtime = new_runtime(credentials: { gemini: { api_key: 'stored' } })
    command_events(runtime, 'gemini/gem-2.5-pro --save')

    assert_equal 'gemini/gem-2.5-pro', saved_settings['model']
  end

  it 'reports the switch to the new model' do
    assert_equal([output('Model switched to mock/other')], command_events(new_runtime, 'mock/other'))
  end

  describe 'with a registered extension provider' do
    before do
      @saved = ENV.fetch('ACME_API_KEY', nil)
      Riffer::Rig::Registrar.new('acme').provider(:acme) { AcmeModelProvider }
    end

    after do
      ENV['ACME_API_KEY'] = @saved
      Riffer::Rig::Providers.unregister(:acme)
    end

    it 'switches to a registered provider whose setup field resolves' do
      ENV['ACME_API_KEY'] = 'sk-acme'
      Riffer::Rig::Registrar.new('acme').provider(
        :acme,
        setup: { fields: [{ name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true }] }
      ) { AcmeModelProvider }
      runtime = new_runtime

      command_events(runtime, 'acme/foo')

      assert_equal 'acme/foo', runtime.model
    end
  end
end
