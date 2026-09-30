# frozen_string_literal: true

module Riffer::Rig::Commands::Model
  extend self

  HINT = 'Use /model provider/name, with a provider from: ' \
         "#{Riffer::Rig::Settings::PROVIDERS.join(', ')}".freeze #: String

  SAVE_UNAVAILABLE = '/model --save is not available in this host'

  # @rbs return: Riffer::Rig::Command
  def command
    Riffer::Rig::Command.new(
      'model',
      description: 'Switch the model for this session: /model provider/name',
      extension: 'core'
    ) { |ctx| run(ctx) }
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs return: void
  def run(ctx)
    model = ctx.args.strip
    return ctx.host.notify(SAVE_UNAVAILABLE, level: :error) if model.split.include?('--save')
    return ctx.say("Model: #{ctx.runtime.model}") if model.empty?

    provider = Riffer::Rig::Settings.provider_for(model)
    return ctx.say(HINT) unless provider && Riffer::Providers::Repository.find(provider)

    missing = missing_credentials(provider, ctx.runtime.credentials)
    return ctx.host.notify(refusal(model, provider, missing), level: :error) unless missing.empty?

    ctx.runtime.model = model
    ctx.say("Model: #{model}")
  end

  private

  # @rbs model: String
  # @rbs provider: String
  # @rbs missing: Array[Symbol]
  # @rbs return: String
  def refusal(model, provider, missing)
    "Not switching to #{model}: #{provider} has no #{missing.join(', ')} in credentials"
  end

  # @rbs provider: String
  # @rbs credentials: Hash[Symbol, Hash[Symbol, String]]
  # @rbs return: Array[Symbol]
  def missing_credentials(provider, credentials)
    required = Riffer::Rig::ProviderSetup[provider]&.fields&.select(&:required) || []
    required.map(&:name).reject { |name| credentials.dig(provider.to_sym, name) }
  end
end
