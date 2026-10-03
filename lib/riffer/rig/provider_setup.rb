# frozen_string_literal: true

class Riffer::Rig::ProviderSetup
  # @dynamic url, chain, sdk, fields
  attr_reader :url #: String?
  attr_reader :chain #: bool
  attr_reader :sdk #: [String, String]?
  attr_reader :fields #: Array[Riffer::Rig::ProviderSetup::Field]

  # @rbs fields: Array[Riffer::Rig::ProviderSetup::Field]
  # @rbs url: String?
  # @rbs chain: bool
  # @rbs sdk: [String, String]?
  # @rbs return: void
  def initialize(fields:, url: nil, chain: false, sdk: nil)
    @url = url
    @chain = chain
    @sdk = sdk&.freeze
    @fields = fields.freeze
    freeze
  end

  AWS_SHARED_CONFIG_REGION = lambda do
    require 'aws-sdk-core'
    Object.const_get(:Aws).shared_config.region
  rescue LoadError
    nil
  end #: ^() -> String?

  # Upstream candidate: riffer's providers could declare their own SDK gem and
  # credential fields, and this table would go.
  TABLE = {
    anthropic: new(
      url: 'https://console.anthropic.com/settings/keys',
      sdk: ['anthropic', '~> 1.69'],
      fields: [Field.new(name: :api_key, env: ['ANTHROPIC_API_KEY'], secret: true, required: true)]
    ),
    openai: new(
      url: 'https://platform.openai.com/api-keys',
      sdk: ['openai', '~> 0.80'],
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
      sdk: ['openai', '~> 0.80'],
      fields: [Field.new(name: :api_key, env: ['OPENROUTER_API_KEY'], secret: true, required: true)]
    ),
    azure_openai: new(
      url: 'https://portal.azure.com',
      sdk: ['openai', '~> 0.80'],
      fields: [
        Field.new(name: :endpoint, env: ['AZURE_OPENAI_ENDPOINT'], secret: false, required: true),
        Field.new(name: :api_key, env: ['AZURE_OPENAI_API_KEY'], secret: true, required: true)
      ]
    ),
    amazon_bedrock: new(
      url: 'https://console.aws.amazon.com/bedrock',
      chain: true,
      sdk: ['aws-sdk-bedrockruntime', '~> 1.0'],
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

  # @rbs missing: Array[Symbol]
  # @rbs return: String
  def missing_fields(missing)
    fields.select { |field| missing.include?(field.name) }
          .map { |field| "#{field.name} (#{field.env.join(' or ')})" }
          .join(', ')
  end

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: Riffer::Rig::ProviderSetup
  def self.from(hash)
    fields = hash.fetch(:fields).map do |field|
      Field.new(
        name: field.fetch(:name),
        env: field.fetch(:env),
        secret: field.fetch(:secret, false),
        required: field.fetch(:required, false),
        fallback: field[:fallback]
      )
    end
    new(fields: fields, url: hash[:url], chain: hash.fetch(:chain, false), sdk: hash[:sdk])
  end

  # @rbs identifier: String | Symbol
  # @rbs return: Riffer::Rig::ProviderSetup?
  def self.[](identifier)
    Riffer::Rig::Providers.setup(identifier) || TABLE[identifier.to_sym]
  end

  # @rbs identifier: String | Symbol
  # @rbs return: Riffer::Rig::ProviderSetup
  def self.for(identifier)
    self[identifier] ||
      new(fields: [Field.new(name: :api_key, env: ["#{identifier.to_s.upcase}_API_KEY"], secret: true, required: true)])
  end
end
