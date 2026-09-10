# frozen_string_literal: true

require 'json'
require 'fileutils'

# Reads and writes the riffer-rig user settings file at
# <tt>~/.riffer/settings.json</tt>.
#
# Example file:
#
#   {
#     "model": "anthropic/claude-sonnet-4-6",
#     "reasoning": "low",
#     "models": {
#       "anthropic/claude-sonnet-4-6": {
#         "input": 3.0,
#         "output": 15.0,
#         "cache_write": 3.75,
#         "cache_read": 0.3
#       }
#     }
#   }
#
# All keys are optional. Missing pricing means cost display is suppressed.
# <tt>"reasoning"</tt> is translated to the appropriate provider-specific
# parameter on each API call; accepted values depend on the provider:
#
# - Anthropic: <tt>"low"</tt>, <tt>"medium"</tt>, <tt>"high"</tt>,
#   <tt>"xhigh"</tt>, <tt>"max"</tt>
# - OpenAI / OpenRouter: <tt>"low"</tt>, <tt>"medium"</tt>, <tt>"high"</tt>,
#   <tt>"xhigh"</tt>
#
# Omitting the key (or supplying an unrecognised value) leaves the model's
# default reasoning behaviour unchanged.
#
module Riffer::Rig::Settings
  extend self

  PATH = File.expand_path('~/.riffer/settings.json') #: String

  DEFAULT_MODEL = 'anthropic/claude-sonnet-4-6'

  REASONING_LEVELS_BY_PROVIDER = {
    'anthropic' => %w[low medium high xhigh max].freeze,
    'openai' => %w[low medium high xhigh].freeze,
    'openrouter' => %w[low medium high xhigh].freeze
  }.freeze #: Hash[String, Array[String]]

  # Returns the configured model string, or +DEFAULT_MODEL+ if not set.
  #
  # @rbs path: String
  # @rbs return: String
  def model(path: PATH)
    read(path).fetch('model', DEFAULT_MODEL)
  end

  # Returns model options for the configured model and reasoning level, ready
  # to pass directly to the Riffer agent's +model_options+.
  #
  # @rbs path: String
  # @rbs return: Hash[Symbol, untyped]
  def model_options(path: PATH)
    provider = provider_for(model(path:))
    base_options(provider).merge(reasoning_options(reasoning_for(path:, provider:), provider))
  end

  # Returns the provider prefix for +model_string+, e.g. <tt>"anthropic"</tt>
  # for <tt>"anthropic/claude-sonnet-4-6"</tt>. Returns +nil+ if the model
  # string contains no slash.
  #
  # @rbs model_string: String
  # @rbs return: String?
  def provider_for(model_string)
    model_string.split('/', 2).first if model_string.include?('/')
  end

  # Returns the pricing for +model+, or +nil+ if not configured.
  #
  # @rbs model: String
  # @rbs path: String
  # @rbs return: Pricing?
  def pricing_for(model, path: PATH)
    entry = read(path).dig('models', model)
    return nil unless entry.is_a?(Hash)

    Pricing.new(
      input: entry.fetch('input', 0).to_f,
      output: entry.fetch('output', 0).to_f,
      cache_write: entry.fetch('cache_write', 0).to_f,
      cache_read: entry.fetch('cache_read', 0).to_f
    )
  end

  private

  # @rbs provider: String?
  # @rbs return: Hash[Symbol, untyped]
  def base_options(provider)
    return { cache_control: { type: :ephemeral } } if provider == 'anthropic'

    {}
  end

  # @rbs path: String
  # @rbs ?provider: String?
  # @rbs return: String?
  def reasoning_for(path: PATH, provider: nil)
    level = read(path)['reasoning']
    valid_levels = (provider && REASONING_LEVELS_BY_PROVIDER[provider]) || []
    valid_levels.include?(level) ? level : nil
  end

  # Maps a reasoning level to the provider-specific model option hash expected
  # by Riffer. Returns an empty hash when +level+ is +nil+.
  #
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

  # The parsed settings file, or an empty hash when the file is absent or
  # malformed.
  #
  # @rbs path: String
  # @rbs return: Hash[String, untyped]
  def read(path)
    return {} unless File.file?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError
    {}
  end
end
