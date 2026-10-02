# frozen_string_literal: true

require 'test_helper'
require 'forwardable'
require 'fileutils'
require 'json'

class AnsweringModelHost
  extend Forwardable

  def_delegators :@null, :capabilities, :confirm, :notify, :progress

  attr_reader :asked #: Array[{ question: String?, secret: bool }]

  # @rbs answer: String?
  # @rbs return: void
  def initialize(answer)
    @null = Riffer::Rig::Hosts::Null.new
    @answer = answer
    @asked = []
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
    FileUtils.rm_f(Riffer::Rig::Credentials::PATH)
    FileUtils.rm_f(Riffer::Rig::Settings::PATH)
  end

  after do
    @saved_env.each { |name, value| ENV[name] = value }
    @saved_keys.each do |provider, key|
      Riffer.config.public_send(provider).api_key = key
    end
    FileUtils.rm_f(Riffer::Rig::Credentials::PATH)
    FileUtils.rm_f(Riffer::Rig::Settings::PATH)
  end

  def command_events(runtime, args)
    events = []
    runtime.run_command('model', args) { |event| events << event }
    events
  end

  def output(text)
    Riffer::Rig::Events::CommandOutput.new('model', text)
  end

  it 'is listed in the Runtime commands' do
    assert_includes Riffer::Rig::Runtime.new('mock/test').commands.map(&:name), 'model'
  end

  it 'switches the Runtime model' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    command_events(runtime, 'mock/other')

    assert_equal 'mock/other', runtime.model
  end

  it 'reports the new model' do
    assert_equal [output('Model: mock/other')], command_events(Riffer::Rig::Runtime.new('mock/test'), 'mock/other')
  end

  it 'reports the current model without arguments' do
    assert_equal [output('Model: mock/test')], command_events(Riffer::Rig::Runtime.new('mock/test'), '')
  end

  it 'sends the next request to the new model' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    command_events(runtime, 'mock/other')
    runtime.agent.provider.stub_response('All done.')
    runtime.ask('hello')

    assert_equal 'other', runtime.agent.provider.calls.last[:model]
  end

  it 'keeps the conversation history' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    runtime.agent.provider.stub_response('First.')
    runtime.ask('hello')
    command_events(runtime, 'mock/other')
    runtime.agent.provider.stub_response('Second.')
    runtime.ask('again')

    assert_equal(
      %w[hello First. again],
      runtime.agent.provider.calls.last[:messages].drop(1).map { |message| message[:content] }
    )
  end

  it 'keeps the tally' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    runtime.agent.provider.stub_response(
      'First.', token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
    )
    runtime.ask('hello')
    command_events(runtime, 'mock/other')

    assert_equal 10, runtime.tally.input_tokens
  end

  it 'rejects a bare name with the providers in the command output' do
    assert_equal(
      [output(
        'Use /model provider/name, with a provider from: ' \
        'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter'
      )],
      command_events(Riffer::Rig::Runtime.new('mock/test'), 'sonnet')
    )
  end

  it 'keeps the model after rejecting a bare name' do
    runtime = Riffer::Rig::Runtime.new('mock/test')
    command_events(runtime, 'sonnet')

    assert_equal 'mock/test', runtime.model
  end

  it 'rejects an unknown provider with the providers in the command output' do
    assert_equal(
      [output(
        'Use /model provider/name, with a provider from: ' \
        'amazon_bedrock, anthropic, azure_openai, gemini, openai, openrouter'
      )],
      command_events(Riffer::Rig::Runtime.new('mock/test'), 'acme/fast')
    )
  end

  describe 'switching to a provider without credentials' do
    def with_openai_sdk_present
      specs = Gem::Specification.method(:find_by_name)
      requirable = Riffer::Rig::SDK.method(:require_gem)
      Gem::Specification.define_singleton_method(:find_by_name) { |*_args| Object.new }
      Riffer::Rig::SDK.define_singleton_method(:require_gem) { |_gem| true }
      yield
    ensure
      Gem::Specification.define_singleton_method(:find_by_name, specs)
      Riffer::Rig::SDK.define_singleton_method(:require_gem, requirable)
    end

    it 'asks for the missing field with hidden input' do
      host = AnsweringModelHost.new('sk-new')
      runtime = Riffer::Rig::Runtime.new('mock/test', host: host)
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_equal [{ question: 'gemini api_key', secret: true }], host.asked
    end

    it 'stores the answered key in auth.json' do
      runtime = Riffer::Rig::Runtime.new('mock/test', host: AnsweringModelHost.new('sk-new'))
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_equal 'sk-new', JSON.parse(File.read(Riffer::Rig::Credentials::PATH)).dig('gemini', 'api_key')
    end

    it 'applies the answered key to the provider config' do
      runtime = Riffer::Rig::Runtime.new('mock/test', host: AnsweringModelHost.new('sk-new'))
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_equal 'sk-new', Riffer.config.gemini.api_key
    end

    it 'updates the Runtime credentials' do
      runtime = Riffer::Rig::Runtime.new('mock/test', host: AnsweringModelHost.new('sk-new'))
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_equal({ api_key: 'sk-new' }, runtime.credentials[:gemini])
    end

    it 'switches the Runtime model' do
      runtime = Riffer::Rig::Runtime.new('mock/test', host: AnsweringModelHost.new('sk-new'))
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_equal 'gemini/gem-2.5-pro', runtime.model
    end

    it 'refuses with one notify when the host cannot ask' do
      events = command_events(Riffer::Rig::Runtime.new('mock/test'), 'gemini/gem-2.5-pro')

      assert_equal(
        [Riffer::Rig::Events::Notify.new(
          'Not switching to gemini/gem-2.5-pro: gemini has no api_key (GEMINI_API_KEY)', :error
        )],
        events
      )
    end

    it 'keeps the model after refusing' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_equal 'mock/test', runtime.model
    end

    it 'refuses a provider missing one of its required fields' do
      runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { azure_openai: { api_key: 'key' } })
      events = nil
      with_openai_sdk_present { events = command_events(runtime, 'azure_openai/gpt-5') }

      assert_equal 'Not switching to azure_openai/gpt-5: azure_openai has no endpoint (AZURE_OPENAI_ENDPOINT)',
                   events.first.message
    end

    it 'does not ask when the Runtime already has the credentials' do
      host = AnsweringModelHost.new('sk-new')
      runtime = Riffer::Rig::Runtime.new('mock/test', host: host, credentials: { gemini: { api_key: 'stored' } })
      command_events(runtime, 'gemini/gem-2.5-pro')

      assert_empty host.asked
    end
  end

  describe 'missing sdk' do
    def with_sdk_absent_and_unbundled
      specs = Gem::Specification.method(:find_by_name)
      bundler = Riffer::Rig::SDK.method(:bundler?)
      Gem::Specification.define_singleton_method(:find_by_name) { |*_args| raise Gem::LoadError, 'not installed' }
      Riffer::Rig::SDK.define_singleton_method(:bundler?) { false }
      yield
    ensure
      Gem::Specification.define_singleton_method(:find_by_name, specs)
      Riffer::Rig::SDK.define_singleton_method(:bundler?, bundler)
    end

    it 'refuses a provider whose SDK gem is missing' do
      runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { openai: { api_key: 'stored' } })
      events = nil
      with_sdk_absent_and_unbundled { events = command_events(runtime, 'openai/gpt-5') }

      assert_equal(
        [Riffer::Rig::Events::Notify.new(
          "openai is not installed; install it with gem install openai -v '~> 0.80' or add it to a Gemfile", :error
        )],
        events
      )
    end

    it 'keeps the model after the SDK refusal' do
      runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { openai: { api_key: 'stored' } })
      with_sdk_absent_and_unbundled { command_events(runtime, 'openai/gpt-5') }

      assert_equal 'mock/test', runtime.model
    end
  end

  describe 'save' do
    def write_home_settings(data)
      FileUtils.mkdir_p(File.dirname(Riffer::Rig::Settings::PATH))
      File.write(Riffer::Rig::Settings::PATH, JSON.generate(data))
    end

    def saved_settings
      return {} unless File.file?(Riffer::Rig::Settings::PATH)

      JSON.parse(File.read(Riffer::Rig::Settings::PATH))
    end

    it 'saves the current model to the home settings' do
      write_home_settings(model: 'gemini/gem-2.5-pro', reasoning: 'high')
      command_events(Riffer::Rig::Runtime.new('mock/test'), '--save')

      assert_equal 'mock/test', saved_settings['model']
    end

    it 'leaves the other settings keys unchanged' do
      write_home_settings(model: 'gemini/gem-2.5-pro', reasoning: 'high')
      command_events(Riffer::Rig::Runtime.new('mock/test'), '--save')

      assert_equal 'high', saved_settings['reasoning']
    end

    it 'saves a new model after switching' do
      runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { gemini: { api_key: 'stored' } })
      command_events(runtime, 'gemini/gem-2.5-pro --save')

      assert_equal 'gemini/gem-2.5-pro', saved_settings['model']
    end

    it 'does not save when the switch is refused' do
      runtime = Riffer::Rig::Runtime.new('mock/test')
      command_events(runtime, 'openai/gpt-5 --save')

      assert_nil saved_settings['model']
    end

    it 'reports the saved model' do
      assert_equal(
        [output('Saved mock/test to settings')],
        command_events(Riffer::Rig::Runtime.new('mock/test'), '--save')
      )
    end
  end
end
