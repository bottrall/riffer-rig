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

  # The switches are on/off settings, so what the agent can do stays a function
  # of the current provider: a switch whose provider cannot take the option
  # contributes nothing, and a switch to such a provider drops it, both silently.
  # @rbs model: String
  # @rbs switches: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped]
  def native_options(model, switches)
    provider = provider_for(model)&.to_sym
    switches.filter_map do |tool, switch|
      next unless provider && NATIVE_TOOLS_BY_PROVIDER[tool]&.key?(provider)

      [tool, switch]
    end.to_h
  end
end
