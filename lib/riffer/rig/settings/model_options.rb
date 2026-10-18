# frozen_string_literal: true

module Riffer::Rig::Settings::ModelOptions
  extend self

  REASONING_LEVELS_BY_PROVIDER = {
    'anthropic' => %w[low medium high xhigh max].freeze,
    'openai' => %w[low medium high xhigh].freeze,
    'openrouter' => %w[low medium high xhigh].freeze
  }.freeze #: Hash[String, Array[String]]

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

  # @rbs level: String
  # @rbs model: String
  # @rbs return: String?
  def reasoning_rejection(level, model)
    levels = levels_for(model)
    return if levels.include?(level)
    return "#{model} accepts no reasoning level" if levels.empty?

    "#{level} is not a reasoning level #{model} accepts; it accepts: #{levels.join(' ')}"
  end

  # @rbs model: String
  # @rbs return: Array[String]
  def levels_for(model)
    provider = provider_for(model)
    (provider && REASONING_LEVELS_BY_PROVIDER[provider]) || []
  end

  # @rbs model: String
  # @rbs reasoning: String?
  # @rbs return: Hash[Symbol, untyped]
  def model_options(model, reasoning)
    provider = provider_for(model)
    level = reasoning if levels_for(model).include?(reasoning)
    base_options(provider).merge(reasoning_options(level, provider))
  end

  private

  # @rbs provider: String?
  # @rbs return: Hash[Symbol, untyped]
  def base_options(provider)
    return { cache_control: { type: :ephemeral } } if provider == 'anthropic'

    {}
  end

  # @rbs level: String?
  # @rbs provider: String?
  # @rbs return: Hash[Symbol, untyped]
  def reasoning_options(level, provider)
    return {} unless level

    case provider
    when 'anthropic'
      { output_config: { effort: level } }
    when 'openai', 'openrouter'
      { reasoning: level }
    else
      {}
    end
  end
end
