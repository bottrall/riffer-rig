# frozen_string_literal: true

module Riffer::Rig::Settings::ModelOptions
  extend self

  MODEL_STRING = %r{\A(?<provider>[^/\s]+)/\S+\z} #: Regexp

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
end
