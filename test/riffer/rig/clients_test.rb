# frozen_string_literal: true

require 'test_helper'
require 'anthropic'
require 'openai'

module Aws
  StaticTokenProvider = Struct.new(:token)
  BedrockRuntime = Module.new
end

class Aws::BedrockRuntime::Client
  attr_reader :options

  def initialize(**options)
    @options = options
  end
end

describe Riffer::Rig::Clients do
  def stub_new(klass)
    klass.define_singleton_method(:new) { |**options| options }
    yield
  ensure
    klass.singleton_class.send(:remove_method, :new)
  end

  def during_prompt(runtime)
    runtime.agent.provider.stub_response('ok')
    result = nil
    runtime.prompt('hello') { |event| result = yield if event.is_a?(Riffer::Rig::Events::TurnEnd) }
    result
  end

  def installed_config
    Riffer::Config.new.tap { |config| Riffer::Rig::Clients.install(config) }
  end

  it 'installs a client Proc for every built-in provider at boot' do
    providers = %i[amazon_bedrock anthropic azure_openai gemini openai openrouter]

    assert(providers.all? { |provider| Riffer.config.public_send(provider).client.is_a?(Proc) })
  end

  it 'builds each parallel Runtime a client with its own key' do
    entered = Queue.new
    release = Queue.new

    clients = stub_new(Anthropic::Client) do
      threads = %w[key-one key-two].map do |key|
        Thread.new do
          runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { anthropic: { api_key: key } })
          during_prompt(runtime) do
            entered << true
            release.pop
            Riffer::Providers::Anthropic.new.send(:client)
          end
        end
      end
      2.times { entered.pop }
      2.times { release << true }
      threads.map(&:value)
    end

    assert_equal [{ api_key: 'key-one' }, { api_key: 'key-two' }], clients
  end

  it 'falls back to Riffer.config when the Runtime has no credentials for the provider' do
    config = installed_config
    config.anthropic.api_key = 'configured'
    runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { openai: { api_key: 'other' } })

    client = stub_new(Anthropic::Client) { during_prompt(runtime) { config.anthropic.client.call } }

    assert_equal({ api_key: 'configured' }, client)
  end

  it 'falls back to Riffer.config outside a prompt' do
    config = installed_config
    config.anthropic.api_key = 'configured'

    client = stub_new(Anthropic::Client) { config.anthropic.client.call }

    assert_equal({ api_key: 'configured' }, client)
  end

  it 'omits an unset anthropic api_key so the SDK reads its own environment' do
    config = installed_config

    client = stub_new(Anthropic::Client) { config.anthropic.client.call }

    assert_empty client
  end

  it 'builds one client per Runtime and provider' do
    config = installed_config
    runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { anthropic: { api_key: 'key' } })

    clients = during_prompt(runtime) { Array.new(2) { config.anthropic.client.call } }

    assert_same clients.first, clients.last
  end

  it 'leaves a host-configured client in place' do
    host_client = Object.new
    config = Riffer::Config.new
    config.anthropic.client = host_client
    Riffer::Rig::Clients.install(config)

    assert_same host_client, config.anthropic.client
  end

  it 'keeps the configured openai base_url beside the Runtime key' do
    config = installed_config
    config.openai.base_url = 'https://proxy.test/v1'
    runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { openai: { api_key: 'key' } })

    client = stub_new(OpenAI::Client) { during_prompt(runtime) { config.openai.client.call } }

    assert_equal({ api_key: 'key', base_url: 'https://proxy.test/v1' }, client)
  end

  it 'points the azure client at the configured endpoint' do
    config = installed_config
    config.azure_openai.endpoint = 'https://azure.test'
    runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { azure_openai: { api_key: 'key' } })

    client = stub_new(OpenAI::Client) { during_prompt(runtime) { config.azure_openai.client.call } }

    assert_equal({ api_key: 'key', base_url: 'https://azure.test' }, client)
  end

  it 'points the openrouter client at OpenRouter' do
    runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { openrouter: { api_key: 'key' } })
    config = installed_config

    client = stub_new(OpenAI::Client) { during_prompt(runtime) { config.openrouter.client.call } }

    assert_equal({ api_key: 'key', base_url: Riffer::Providers::OpenRouter::BASE_URL }, client)
  end

  it 'passes the Runtime key to the gemini client' do
    runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { gemini: { api_key: 'key' } })
    config = installed_config

    client = stub_new(Riffer::Providers::Gemini::Client) { during_prompt(runtime) { config.gemini.client.call } }

    assert_equal({ api_key: 'key' }, client)
  end

  it 'authenticates bedrock with the Runtime key as a bearer token' do
    config = installed_config
    config.amazon_bedrock.region = 'us-east-1'
    runtime = Riffer::Rig::Runtime.new('mock/test', credentials: { amazon_bedrock: { api_key: 'token' } })

    client = during_prompt(runtime) { config.amazon_bedrock.client.call }

    assert_equal(
      {
        region: 'us-east-1',
        token_provider: Aws::StaticTokenProvider.new('token'),
        auth_scheme_preference: ['httpBearerAuth']
      },
      client.options
    )
  end

  it 'leaves bedrock to the AWS credential chain without a token' do
    config = installed_config
    config.amazon_bedrock.region = 'us-east-1'

    assert_equal({ region: 'us-east-1' }, config.amazon_bedrock.client.call.options)
  end
end
