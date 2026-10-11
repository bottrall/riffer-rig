# frozen_string_literal: true

module Riffer::Rig::Commands::Model
  extend self

  SAVE = '--save' #: String

  # @rbs return: Riffer::Rig::Command
  def command
    Riffer::Rig::Command.new(
      'model',
      description: 'Switch the model for this session: /model provider/name, /model --save',
      extension: :core
    ) { |ctx| run(ctx) }
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs return: void
  def run(ctx)
    words = ctx.args.split
    save = words.delete(SAVE)
    model = words.join(' ')

    if model.empty?
      return ctx.say("Model: #{ctx.runtime.model}") unless save

      Riffer::Rig::Settings.store_model(ctx.runtime.model)
      return ctx.say("Saved #{ctx.runtime.model} to settings")
    end

    provider = Riffer::Rig::Settings.provider_for(model)
    return ctx.say(hint) unless provider && Riffer::Providers::Repository.find(provider)
    return unless ready?(ctx, model, provider)

    ctx.runtime.model = model
    Riffer::Rig::Settings.store_model(model) if save
    ctx.say("Model: #{model}")
  end

  private

  # @rbs return: String
  def hint
    "Use /model provider/name, with a provider from: #{Riffer::Rig::Settings.provider_list}"
  end

  # The same setup flows the Loader runs when it builds a Runtime: the
  # provider's SDK gem, then its credentials, asked for when the host can ask.
  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs model: String
  # @rbs provider: String
  # @rbs return: bool
  def ready?(ctx, model, provider)
    setup = Riffer::Rig::ProviderSetup.registered_setup(provider)
    return true unless setup

    sdk = setup.sdk
    if sdk
      message = Riffer::Rig::SDK.ensure(sdk[0], sdk[1], host: ctx.host)
      if message
        ctx.host.notify(message, level: :error)
        return false
      end
    end

    credentials_ready?(ctx, model, provider, setup)
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs model: String
  # @rbs provider: String
  # @rbs setup: Riffer::Rig::ProviderSetup
  # @rbs return: bool
  def credentials_ready?(ctx, model, provider, setup)
    missing = setup.fields.select(&:required)
                   .map(&:name)
                   .reject { |name| ctx.runtime.credentials.dig(provider.to_sym, name) }
    return true if missing.empty?

    empty = {} #: Hash[Symbol, String]
    stored = ctx.runtime.credentials.fetch(provider.to_sym, empty)
    resolution = Riffer::Rig::Credentials.install(provider, host: ctx.host, known: stored)
    if resolution.missing.any?
      refuse(ctx, model, provider, missing & resolution.missing)
      false
    else
      ctx.runtime.merge_credentials(provider.to_sym, stored.merge(resolution.values))
      true
    end
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs model: String
  # @rbs provider: String
  # @rbs missing: Array[Symbol]
  # @rbs return: void
  def refuse(ctx, model, provider, missing)
    wanted = Riffer::Rig::ProviderSetup.for(provider).missing_fields(missing)
    ctx.host.notify("Not switching to #{model}: #{provider} has no #{wanted}", level: :error)
  end
end
