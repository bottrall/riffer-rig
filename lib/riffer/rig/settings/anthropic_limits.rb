# frozen_string_literal: true

class Riffer::Rig::Settings::AnthropicLimits
  # @rbs @config: Riffer::Config
  # @rbs @max_tokens: Hash[String, Integer?]

  # @rbs config: Riffer::Config
  # @rbs return: void
  def initialize(config)
    @config = config
    @max_tokens = {}
  end

  # @rbs model_id: String
  # @rbs return: Integer?
  def max_tokens(model_id)
    @max_tokens.fetch(model_id) { @max_tokens[model_id] = retrieve_max_tokens(model_id) }
  end

  private

  # @rbs model_id: String
  # @rbs return: Integer?
  def retrieve_max_tokens(model_id)
    client.models.retrieve(model_id).max_tokens
  rescue ::Anthropic::Errors::Error
    nil
  end

  # @rbs return: ::Anthropic::Client
  def client
    # Resolved as riffer's Anthropic provider resolves its client, so the
    # lookup authenticates the way the request does.
    Riffer::Helpers::CallOrValue.resolve(@config.anthropic.client) ||
      ::Anthropic::Client.new(**{ api_key: @config.anthropic.api_key }.compact)
  end
end
