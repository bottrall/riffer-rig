# frozen_string_literal: true

module Riffer::Rig::Settings::ModelOptions
  extend self

  MODEL_STRING = %r{\A(?<provider>[^/\s]+)/\S+\z} #: Regexp

  # Upstream candidate: riffer's Anthropic, OpenAI and Azure OpenAI classes read
  # the web_search option and OpenRouter passes unknown options through to its
  # API, but the provider seam cannot yet answer which provider takes which
  # option, so rig keeps the mapping until it can. Mock consumes web_search, so
  # tests and embedders can exercise the switches.
  NATIVE_TOOLS_BY_PROVIDER = {
    web_search: { anthropic: true, openai: true, azure_openai: true, mock: true }.freeze
  }.freeze #: Hash[Symbol, Hash[Symbol, bool]]

  # Upstream candidate: riffer passes model_options to each provider's API
  # unchanged, so rig names every provider's own output limit parameter until
  # riffer accepts a provider-neutral option and translates it, as it does for
  # reasoning.
  MAX_TOKENS_PARAMETERS = {
    anthropic: %i[max_tokens].freeze,
    openai: %i[max_output_tokens].freeze,
    azure_openai: %i[max_output_tokens].freeze,
    gemini: %i[maxOutputTokens].freeze,
    openrouter: %i[max_tokens].freeze,
    amazon_bedrock: %i[inference_config max_tokens].freeze,
    mock: %i[max_tokens].freeze
  }.freeze #: Hash[Symbol, Array[Symbol]]

  # Every other provider's API falls back to the model's own limit, but riffer's
  # Anthropic provider sends 4096 unless told otherwise, and thinking spends
  # from that same budget.
  MAX_TOKENS_REQUIRED = %i[anthropic].freeze #: Array[Symbol]

  DEFAULT_MAX_TOKENS = 64_000

  # @rbs model: String
  # @rbs return: String?
  def provider_for(model)
    model[MODEL_STRING, :provider]
  end

  # @rbs model: String
  # @rbs return: String?
  def rejection(model)
    provider = provider_for(model)
    return if provider && Riffer::Providers::Repository.find(provider)

    "#{model} is not a provider/name model string; the provider is one of: #{Riffer::Rig::Providers.list}"
  end

  # @rbs level: String?
  # @rbs return: String?
  def reasoning_level(level)
    level if level && Riffer::Agent::Config::REASONING_LEVELS.include?(level.to_sym)
  end

  # @rbs level: String
  # @rbs return: String?
  def reasoning_rejection(level)
    return if reasoning_level(level)

    "#{level} is not a reasoning level; riffer accepts: #{Riffer::Agent::Config::REASONING_LEVELS.join(' ')}"
  end

  # @rbs model: String
  # @rbs return: Hash[Symbol, untyped]
  def model_options(model)
    return { cache_control: { type: :ephemeral } } if provider_for(model) == 'anthropic'

    {}
  end

  # @rbs model: String
  # @rbs max_tokens: Integer?
  # @rbs return: Hash[Symbol, untyped]
  def max_tokens_options(model, max_tokens)
    provider = provider_for(model)&.to_sym
    path = provider && MAX_TOKENS_PARAMETERS[provider]
    limit = max_tokens || (DEFAULT_MAX_TOKENS if MAX_TOKENS_REQUIRED.include?(provider))
    return {} unless path && limit

    innermost = { path.fetch(-1) => limit } #: Hash[Symbol, untyped]
    path.reverse.drop(1).reduce(innermost) { |nested, parent| { parent => nested } }
  end

  # @rbs model: String
  # @rbs switches: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped]
  def native_options(model, switches)
    provider = provider_for(model)&.to_sym
    switches.filter_map do |tool, switch|
      # Dropped silently: a switch is an on/off setting, so what the agent can
      # do follows the current provider.
      next unless provider && NATIVE_TOOLS_BY_PROVIDER[tool]&.key?(provider)

      [tool, switch]
    end.to_h
  end
end
