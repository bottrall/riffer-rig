# frozen_string_literal: true

require 'json'
require 'fileutils'

module Riffer::Rig::Settings
  extend self

  PATH = File.expand_path('~/.riffer/settings.json') #: String

  DEFAULT_MODEL = 'anthropic/claude-sonnet-4-6'

  REASONING_LEVELS_BY_PROVIDER = {
    'anthropic' => %w[low medium high xhigh max].freeze,
    'openai' => %w[low medium high xhigh].freeze,
    'openrouter' => %w[low medium high xhigh].freeze
  }.freeze #: Hash[String, Array[String]]

  # @rbs path: String
  # @rbs return: String
  def model(path: PATH)
    read(path).model || DEFAULT_MODEL
  end

  # @rbs path: String
  # @rbs return: Hash[Symbol, untyped]
  def model_options(path: PATH)
    provider = provider_for(model(path:))
    base_options(provider).merge(reasoning_options(reasoning_for(path:, provider:), provider))
  end

  # @rbs model_string: String
  # @rbs return: String?
  def provider_for(model_string)
    model_string.split('/', 2).first if model_string.include?('/')
  end

  # @rbs model: String
  # @rbs path: String
  # @rbs return: Pricing?
  def pricing_for(model, path: PATH)
    read(path).models[model]
  end

  private

  # @rbs provider: String?
  # @rbs return: Hash[Symbol, untyped]
  def base_options(provider)
    return { cache_control: { type: :ephemeral } } if provider == 'anthropic'

    {}
  end

  # @rbs path: String
  # @rbs provider: String?
  # @rbs return: String?
  def reasoning_for(path: PATH, provider: nil)
    level = read(path).reasoning
    valid_levels = (provider && REASONING_LEVELS_BY_PROVIDER[provider]) || []
    valid_levels.include?(level) ? level : nil
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

  # @rbs path: String
  # @rbs return: Document
  def read(path)
    return Document.new({}) unless File.file?(path)

    Document.new(JSON.parse(File.read(path)))
  rescue JSON::ParserError
    Document.new({})
  end
end
