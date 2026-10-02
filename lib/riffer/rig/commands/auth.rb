# frozen_string_literal: true

module Riffer::Rig::Commands::Auth
  extend self

  HINT = 'Use /auth <provider> or /auth remove <provider>, with a provider from: ' \
         "#{Riffer::Rig::Settings::PROVIDERS.join(', ')}".freeze #: String

  USAGE = 'Use /auth, /auth <provider> or /auth remove <provider>' #: String

  # @rbs return: Riffer::Rig::Command
  def command
    Riffer::Rig::Command.new(
      'auth',
      description: 'Show, re-run or remove provider credentials',
      extension: 'core'
    ) { |ctx| run(ctx) }
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs return: void
  def run(ctx)
    words = ctx.args.split
    return ctx.say(list) if words.empty?
    return remove(ctx, words[1]) if words[0] == 'remove' && words.length == 2
    return rerun(ctx, words[0]) if words.length == 1

    ctx.say(USAGE)
  end

  private

  # @rbs return: String
  def list
    statuses = Riffer::Rig::Settings::PROVIDERS.to_h do |identifier|
      [identifier, Riffer::Rig::Credentials.status(identifier)]
    end
    width = statuses.keys.map { |identifier| identifier.to_s.length }.max || 0
    statuses.map { |identifier, status| "#{identifier.to_s.ljust(width)}  #{status}" }.join("\n")
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs identifier: String
  # @rbs return: void
  def rerun(ctx, identifier)
    return ctx.say(HINT) unless Riffer::Providers::Repository.find(identifier)

    provider = identifier.to_sym
    resolution = Riffer::Rig::Credentials.resolve(provider, host: ctx.host)
    Riffer::Rig::Credentials.apply(provider, resolution.values)
    ctx.runtime.merge_credentials(provider, resolution.values)
    return ctx.host.notify(refusal(provider, resolution.missing), level: :error) unless resolution.missing.empty?

    ctx.say("Updated #{provider} credentials")
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs identifier: String
  # @rbs return: void
  def remove(ctx, identifier)
    return ctx.say(HINT) unless Riffer::Providers::Repository.find(identifier)

    Riffer::Rig::Credentials.remove(identifier)
    ctx.say("Removed stored #{identifier} credentials")
  end

  # @rbs provider: Symbol
  # @rbs missing: Array[Symbol]
  # @rbs return: String
  def refusal(provider, missing)
    setup = Riffer::Rig::ProviderSetup.for(provider)
    fields = setup.fields.select { |field| missing.include?(field.name) }
    wanted = fields.map { |field| "#{field.name} (#{field.env.join(' or ')})" }.join(', ')
    "#{provider} still has no #{wanted}"
  end
end
