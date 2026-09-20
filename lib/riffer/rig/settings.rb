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

  # @rbs identifier: String
  # @rbs path: String
  # @rbs return: Hash[String, String]
  def provider_fields(identifier, path: PATH)
    read(path).providers[identifier] || {}
  end

  # @rbs identifier: String
  # @rbs fields: Hash[String, String]
  # @rbs path: String
  # @rbs return: void
  def store_provider(identifier, fields, path: PATH)
    update_providers(path) do |providers|
      providers.merge(identifier => fields) { |_identifier, stored, given| stored.merge(given) }
    end
  end

  # @rbs identifier: String
  # @rbs path: String
  # @rbs return: void
  def remove_provider(identifier, path: PATH)
    update_providers(path) { |providers| providers.except(identifier) }
  end

  private

  # @rbs path: String
  # @rbs &: (Hash[String, Hash[String, String]]) -> Hash[String, Hash[String, String]]
  # @rbs return: void
  def update_providers(path)
    source = read_source(path)
    current = Document.new(source).providers
    providers = yield current
    return if providers == current

    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    document = providers.empty? ? source.except('providers') : source.merge('providers' => providers)
    File.write(path, JSON.pretty_generate(document))
  end

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
    Document.new(read_source(path))
  end

  # @rbs path: String
  # @rbs return: Hash[String, untyped]
  def read_source(path)
    return {} unless File.file?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError
    {}
  end
end
