# frozen_string_literal: true

require 'json'
require 'fileutils'

module Riffer::Rig::Settings
  extend self

  PATH = File.expand_path('~/.riffer/settings.json') #: String

  REASONING_LEVELS_BY_PROVIDER = {
    'anthropic' => %w[low medium high xhigh max].freeze,
    'openai' => %w[low medium high xhigh].freeze,
    'openrouter' => %w[low medium high xhigh].freeze
  }.freeze #: Hash[String, Array[String]]

  MODEL_STRING = %r{\A(?<provider>[^/\s]+)/\S+\z} #: Regexp

  # @rbs return: Array[Symbol]
  def providers
    Riffer::Rig::Providers.identifiers
  end

  # @rbs path: String
  # @rbs return: Hash[Symbol, untyped]
  def read(path)
    return {} unless File.file?(path)

    source = JSON.parse(File.read(path), symbolize_names: true)
    source.is_a?(Hash) ? source : {}
  rescue JSON::ParserError
    {}
  end

  # MCP servers merge by name, whole, so a home server's headers never reach a
  # project server's url.
  # @rbs home: Hash[Symbol, untyped]
  # @rbs project: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped]
  def merge(home, project)
    merged = deep_merge(home, project)
    home_mcp = home[:mcp]
    project_mcp = project[:mcp]
    if home_mcp.is_a?(Hash) && project_mcp.is_a?(Hash)
      merged = merged.merge(mcp: Riffer::Rig::Mcp.merge(home_mcp, project_mcp))
    end
    disabled = [home, project].flat_map { |scope| Document.new(scope).disabled }.uniq
    return merged if disabled.empty?

    extensions = merged[:extensions].is_a?(Hash) ? merged[:extensions] : {} #: Hash[Symbol, untyped]
    merged.merge(extensions: extensions.merge(disabled: disabled))
  end

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

    "#{model} is not a provider/name model string; the provider is one of: #{providers.join(', ')}"
  end

  # @rbs model: String
  # @rbs reasoning: String?
  # @rbs return: Hash[Symbol, untyped]
  def model_options(model, reasoning)
    provider = provider_for(model)
    levels = (provider && REASONING_LEVELS_BY_PROVIDER[provider]) || []
    level = reasoning if levels.include?(reasoning)
    base_options(provider).merge(reasoning_options(level, provider))
  end

  # @rbs model: String
  # @rbs path: String
  # @rbs return: void
  def store_model(model, path: PATH)
    write(path, read(path).merge(model: model))
  end

  # @rbs identifier: String
  # @rbs path: String
  # @rbs return: Hash[String, String]
  def provider_fields(identifier, path: PATH)
    Document.new(read(path)).providers[identifier] || {}
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

  # @rbs home: Hash[Symbol, untyped]
  # @rbs project: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped]
  def deep_merge(home, project)
    home.merge(project) do |_key, earlier, later|
      earlier.is_a?(Hash) && later.is_a?(Hash) ? deep_merge(earlier, later) : later
    end
  end

  # @rbs path: String
  # @rbs &: (Hash[String, Hash[String, String]]) -> Hash[String, Hash[String, String]]
  # @rbs return: void
  def update_providers(path)
    source = read(path)
    current = Document.new(source).providers
    providers = yield current
    return if providers == current

    write(path, providers.empty? ? source.except(:providers) : source.merge(providers: providers))
  end

  # @rbs path: String
  # @rbs document: Hash[Symbol, untyped]
  # @rbs return: void
  def write(path, document)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    File.write(path, JSON.pretty_generate(document))
  end

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
