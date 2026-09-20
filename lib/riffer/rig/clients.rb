# frozen_string_literal: true

# Upstream candidate: a per-agent provider option in riffer replaces these
# process-wide client Procs. riffer never falls back to a provider's own
# build_client once a Proc is configured, so each builder reproduces its
# provider's build_client, reading Riffer.config wherever the current Runtime
# holds no api_key.
module Riffer::Rig::Clients
  extend self

  # Azure and OpenRouter pass nil through uncompacted: they borrow the OpenAI
  # SDK, which would otherwise fall back to OPENAI_API_KEY / OPENAI_BASE_URL
  # and send an OpenAI credential to the other vendor.
  BUILDERS = {
    amazon_bedrock: lambda do |settings, api_key|
      token = api_key || settings.api_token
      region = { region: settings.region }.compact
      if token && !token.empty?
        ::Aws::BedrockRuntime::Client.new(
          **region,
          token_provider: ::Aws::StaticTokenProvider.new(token),
          auth_scheme_preference: ['httpBearerAuth']
        )
      else
        ::Aws::BedrockRuntime::Client.new(**region)
      end
    end,
    anthropic: lambda do |settings, api_key|
      ::Anthropic::Client.new(**{ api_key: api_key || settings.api_key }.compact)
    end,
    azure_openai: lambda do |settings, api_key|
      ::OpenAI::Client.new(
        api_key: api_key || settings.api_key || ENV.fetch('AZURE_OPENAI_API_KEY', nil),
        base_url: settings.endpoint || ENV.fetch('AZURE_OPENAI_ENDPOINT', nil)
      )
    end,
    gemini: lambda do |settings, api_key|
      Riffer::Providers::Gemini::Client.new(**{ api_key: api_key || settings.api_key }.compact)
    end,
    openai: lambda do |settings, api_key|
      ::OpenAI::Client.new(**{ api_key: api_key || settings.api_key, base_url: settings.base_url }.compact)
    end,
    openrouter: lambda do |settings, api_key|
      ::OpenAI::Client.new(
        api_key: api_key || settings.api_key || ENV.fetch('OPENROUTER_API_KEY', nil),
        base_url: Riffer::Providers::OpenRouter::BASE_URL
      )
    end
  }.freeze #: Hash[Symbol, ^(untyped, String?) -> untyped]

  # Installs one client Proc per built-in provider. A client the host already
  # configured is left in place.
  #
  # @rbs config: Riffer::Config
  # @rbs return: void
  def install(config)
    BUILDERS.each_key do |provider|
      config.public_send(provider).client ||= -> { client(provider, config) }
    end
  end

  private

  # @rbs provider: Symbol
  # @rbs config: Riffer::Config
  # @rbs return: untyped
  def client(provider, config)
    build = ->(api_key) { BUILDERS.fetch(provider).call(config.public_send(provider), api_key) }
    runtime = Riffer::Rig::Runtime.current
    return build.call(nil) unless runtime

    runtime.client(provider) { build.call(runtime.credentials.dig(provider, :api_key)) }
  end
end
