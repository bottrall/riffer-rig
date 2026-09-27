# frozen_string_literal: true

class Riffer::Rig::ProviderSetup
  # @dynamic url, chain, fields
  attr_reader :url #: String?
  attr_reader :chain #: bool
  attr_reader :fields #: Array[Riffer::Rig::ProviderSetup::Field]

  # @rbs fields: Array[Riffer::Rig::ProviderSetup::Field]
  # @rbs url: String?
  # @rbs chain: bool
  # @rbs return: void
  def initialize(fields:, url: nil, chain: false)
    @url = url
    @chain = chain
    @fields = fields.freeze
    freeze
  end

  AWS_SHARED_CONFIG_REGION = lambda do
    require 'aws-sdk-core'
    Object.const_get(:Aws).shared_config.region
  rescue LoadError
    nil
  end #: ^() -> String?

  # Upstream candidate: each riffer provider could declare its own credential
  # fields, and this table would go.
  TABLE = {
    anthropic: new(
      url: 'https://console.anthropic.com/settings/keys',
      fields: [Field.new(name: :api_key, env: ['ANTHROPIC_API_KEY'], secret: true, required: true)]
    ),
    openai: new(
      url: 'https://platform.openai.com/api-keys',
      fields: [
        Field.new(name: :api_key, env: ['OPENAI_API_KEY'], secret: true, required: true),
        Field.new(name: :base_url, env: ['OPENAI_BASE_URL'], secret: false, required: false)
      ]
    ),
    gemini: new(
      url: 'https://aistudio.google.com/app/apikey',
      fields: [Field.new(name: :api_key, env: ['GEMINI_API_KEY'], secret: true, required: true)]
    ),
    openrouter: new(
      url: 'https://openrouter.ai/keys',
      fields: [Field.new(name: :api_key, env: ['OPENROUTER_API_KEY'], secret: true, required: true)]
    ),
    azure_openai: new(
      url: 'https://portal.azure.com',
      fields: [
        Field.new(name: :endpoint, env: ['AZURE_OPENAI_ENDPOINT'], secret: false, required: true),
        Field.new(name: :api_key, env: ['AZURE_OPENAI_API_KEY'], secret: true, required: true)
      ]
    ),
    amazon_bedrock: new(
      url: 'https://console.aws.amazon.com/bedrock',
      chain: true,
      fields: [
        Field.new(
          name: :region,
          env: %w[AWS_REGION AWS_DEFAULT_REGION],
          secret: false,
          required: true,
          fallback: AWS_SHARED_CONFIG_REGION
        ),
        Field.new(name: :api_token, env: ['AWS_BEARER_TOKEN_BEDROCK'], secret: true, required: false)
      ]
    )
  }.freeze #: Hash[Symbol, Riffer::Rig::ProviderSetup]

  # @rbs identifier: String | Symbol
  # @rbs return: Riffer::Rig::ProviderSetup?
  def self.[](identifier)
    TABLE[identifier.to_sym]
  end

  # @rbs identifier: String | Symbol
  # @rbs return: Riffer::Rig::ProviderSetup
  def self.for(identifier)
    self[identifier] ||
      new(fields: [Field.new(name: :api_key, env: ["#{identifier.to_s.upcase}_API_KEY"], secret: true, required: true)])
  end
end
