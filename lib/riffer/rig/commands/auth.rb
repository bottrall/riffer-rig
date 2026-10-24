# frozen_string_literal: true

module Riffer::Rig::Commands::Auth
  extend self

  USAGE = 'Use /auth, /auth <provider> or /auth remove <provider>' #: String

  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: Riffer::Rig::Command
  def command(env:, auth_path:, settings_path:)
    Riffer::Rig::Command.new(
      'auth',
      description: 'Show, re-run or remove provider credentials',
      extension: :core
    ) { |ctx| run(ctx, env:, auth_path:, settings_path:) }
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: void
  def run(ctx, env:, auth_path:, settings_path:)
    words = ctx.args.split
    return list(ctx, env:, auth_path:) if words.empty?
    return remove(ctx, words[1], auth_path:, settings_path:) if words[0] == 'remove' && words.length == 2
    return rerun(ctx, words[0], env:, auth_path:, settings_path:) if words.length == 1

    ctx.say(USAGE)
  end

  private

  # @rbs return: String
  def hint
    'Use /auth <provider> or /auth remove <provider>, with a provider from: ' \
      "#{Riffer::Rig::Providers.list}"
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs return: void
  def list(ctx, env:, auth_path:)
    statuses = Riffer::Rig::Providers.identifiers.to_h do |identifier|
      [identifier, Riffer::Rig::Credentials.status(identifier, env:, auth_path:)]
    end
    unreadable = statuses.values.grep(String) #: Array[String]
    return ctx.host.notify(unreadable.first, level: :error) if unreadable.any?

    width = statuses.keys.map { |identifier| identifier.to_s.length }.max || 0
    ctx.say(statuses.map { |identifier, status| "#{identifier.to_s.ljust(width)}  #{status}" }.join("\n"))
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs identifier: String
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: void
  def rerun(ctx, identifier, env:, auth_path:, settings_path:)
    return ctx.say(hint) unless Riffer::Providers::Repository.find(identifier)

    provider = identifier.to_sym
    resolution = Riffer::Rig::Credentials.install(provider, host: ctx.host, env:, auth_path:, settings_path:)
    return ctx.host.notify(resolution, level: :error) if resolution.is_a?(String)

    if resolution.missing.any?
      missing_fields = Riffer::Rig::ProviderSetup.for(provider).missing_fields(resolution.missing)
      ctx.host.notify("#{provider} still has no #{missing_fields}", level: :error)
    else
      ctx.runtime.merge_credentials(provider, resolution.values)
      ctx.say("Updated #{provider} credentials")
    end
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs identifier: String
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: void
  def remove(ctx, identifier, auth_path:, settings_path:)
    return ctx.say(hint) unless Riffer::Providers::Repository.find(identifier)

    refusal = Riffer::Rig::Credentials.remove(identifier, auth_path:, settings_path:)
    return ctx.host.notify(refusal, level: :error) if refusal

    ctx.say("Removed stored #{identifier} credentials")
  end
end
