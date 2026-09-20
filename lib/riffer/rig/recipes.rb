# frozen_string_literal: true

module Riffer::Rig::Recipes
  extend self

  # @rbs!
  #   type field = { name: Symbol, env: Array[String], secret: bool, required: bool, ?fallback: ^() -> String? }
  #   type recipe = { ?url: String, ?chain: bool, fields: Array[field] }

  AWS_SHARED_CONFIG_REGION = lambda do
    require 'aws-sdk-core'
    Object.const_get(:Aws).shared_config.region
  rescue LoadError
    nil
  end #: ^() -> String?

  # Upstream candidate: each riffer provider could declare its own credential
  # fields, and this table would go.
  TABLE = {
    anthropic: {
      url: 'https://console.anthropic.com/settings/keys',
      fields: [{ name: :api_key, env: ['ANTHROPIC_API_KEY'], secret: true, required: true }]
    },
    openai: {
      url: 'https://platform.openai.com/api-keys',
      fields: [
        { name: :api_key, env: ['OPENAI_API_KEY'], secret: true, required: true },
        { name: :base_url, env: ['OPENAI_BASE_URL'], secret: false, required: false }
      ]
    },
    gemini: {
      url: 'https://aistudio.google.com/app/apikey',
      fields: [{ name: :api_key, env: ['GEMINI_API_KEY'], secret: true, required: true }]
    },
    openrouter: {
      url: 'https://openrouter.ai/keys',
      fields: [{ name: :api_key, env: ['OPENROUTER_API_KEY'], secret: true, required: true }]
    },
    azure_openai: {
      url: 'https://portal.azure.com',
      fields: [
        { name: :endpoint, env: ['AZURE_OPENAI_ENDPOINT'], secret: false, required: true },
        { name: :api_key, env: ['AZURE_OPENAI_API_KEY'], secret: true, required: true }
      ]
    },
    amazon_bedrock: {
      url: 'https://console.aws.amazon.com/bedrock',
      chain: true,
      fields: [
        {
          name: :region, env: %w[AWS_REGION AWS_DEFAULT_REGION], secret: false, required: true,
          fallback: AWS_SHARED_CONFIG_REGION
        },
        { name: :api_token, env: ['AWS_BEARER_TOKEN_BEDROCK'], secret: true, required: false }
      ]
    }
  }.freeze #: Hash[Symbol, recipe]

  # @rbs identifier: String | Symbol
  # @rbs return: recipe?
  def [](identifier)
    TABLE[identifier.to_sym]
  end

  # @rbs identifier: String | Symbol
  # @rbs return: recipe
  def for(identifier)
    self[identifier] || generic(identifier)
  end

  private

  # @rbs identifier: String | Symbol
  # @rbs return: recipe
  def generic(identifier)
    { fields: [{ name: :api_key, env: ["#{identifier.to_s.upcase}_API_KEY"], secret: true, required: true }] }
  end
end
