# frozen_string_literal: true

module Riffer::Rig::Commands::Model
  extend self

  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: Riffer::Rig::Command
  def command(env:, auth_path:, settings_path:)
    Riffer::Rig::Command.new(
      'model',
      description: 'Switch the model for this session: /model provider/name, /model --save',
      extension: :core
    ) { |ctx| run(ctx, env:, auth_path:, settings_path:) }
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: void
  def run(ctx, env:, auth_path:, settings_path:)
    current = ctx.runtime.model
    Riffer::Rig::Commands::Switch.run(
      ctx,
      label: 'Model',
      shown: current,
      current: current,
      unset: 'No model is in effect to save',
      saved_to: settings_path,
      store: ->(model) { Riffer::Rig::Settings::File.store_model(model, path: settings_path) }
    ) { |model| switched?(ctx, model, env:, auth_path:, settings_path:) }
  end

  private

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs model: String
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: bool
  def switched?(ctx, model, env:, auth_path:, settings_path:)
    provider = Riffer::Rig::Settings::ModelOptions.provider_for(model)
    unless provider && Riffer::Providers::Repository.find(provider)
      ctx.say(hint)
      return false
    end
    return false unless ready?(ctx, model, provider, env:, auth_path:, settings_path:)

    ctx.runtime.model = model
    true
  end

  # @rbs return: String
  def hint
    "Use /model provider/name, with a provider from: #{Riffer::Rig::Providers.list}"
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs model: String
  # @rbs provider: String
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: bool
  def ready?(ctx, model, provider, env:, auth_path:, settings_path:)
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

    credentials_ready?(ctx, model, provider, setup, env:, auth_path:, settings_path:)
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs model: String
  # @rbs provider: String
  # @rbs setup: Riffer::Rig::ProviderSetup
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: bool
  def credentials_ready?(ctx, model, provider, setup, env:, auth_path:, settings_path:)
    missing = setup.fields.select(&:required)
                   .map(&:name)
                   .reject { |name| ctx.runtime.credentials.dig(provider.to_sym, name) }
    return true if missing.empty?

    empty = {} #: Hash[Symbol, String]
    stored = ctx.runtime.credentials.fetch(provider.to_sym, empty)
    resolution = Riffer::Rig::Credentials.install(
      provider, host: ctx.host, env:, auth_path:, settings_path:, known: stored
    )
    if resolution.is_a?(String)
      ctx.host.notify(resolution, level: :error)
      false
    elsif resolution.missing.any?
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
