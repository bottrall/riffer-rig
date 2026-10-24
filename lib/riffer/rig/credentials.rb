# frozen_string_literal: true

module Riffer::Rig::Credentials
  extend self

  PATH = Riffer::Rig::Directories.riffer(Dir.home, 'auth.json') #: String

  # @rbs @applied: Hash[Symbol, Hash[Symbol, String]]
  @applied = {} #: Hash[Symbol, Hash[Symbol, String]]

  # @rbs identifier: String | Symbol
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs setup: Riffer::Rig::ProviderSetup
  # @rbs env: Riffer::Rig::Env
  # @rbs config: Riffer::Config?
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs known: Hash[Symbol, String]
  # @rbs return: (Resolution | String)
  def install(
    identifier,
    host:,
    setup: Riffer::Rig::ProviderSetup.for(identifier),
    env: Riffer::Rig::Env.new,
    config: Riffer.config,
    auth_path: PATH,
    settings_path: Riffer::Rig::Settings::File::PATH,
    known: {}
  )
    resolution = resolve(identifier, host:, setup:, env:, auth_path:, settings_path:)
    return resolution if resolution.is_a?(String)

    missing = resolution.missing - known.keys
    apply(identifier, resolution.values, config: config) if config && missing.empty?
    Resolution.new(values: resolution.values, missing: missing)
  end

  # @rbs identifier: String | Symbol
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs label: String
  # @rbs setup: Riffer::Rig::ProviderSetup
  # @rbs config: Riffer::Config?
  # @rbs settings_path: String
  # @rbs known: Hash[Symbol, String]
  # @rbs return: (Hash[Symbol, String] | String)
  def install_values(
    identifier,
    host:,
    env:,
    auth_path:,
    label: identifier.to_s,
    setup: Riffer::Rig::ProviderSetup.for(identifier),
    config: Riffer.config,
    settings_path: Riffer::Rig::Settings::File::PATH,
    known: {}
  )
    resolution = install(identifier, host:, setup:, env:, config:, auth_path:, settings_path:, known:)
    return resolution if resolution.is_a?(String)
    return resolution.values if resolution.missing.empty?

    "#{label} has no #{setup.missing_fields(resolution.missing)}; " \
      'set it in the environment or run riffer interactively to paste it' \
      "#{" (create one at #{setup.url})" if setup.url}"
  end

  # A registered extension provider has no Riffer::Config member, so the
  # assignment stays built-ins-only.
  # @rbs identifier: String | Symbol
  # @rbs values: Hash[Symbol, String]
  # @rbs config: Riffer::Config
  # @rbs return: void
  def apply(identifier, values, config: Riffer.config)
    @applied[identifier.to_sym] = values.dup.freeze
    return unless Riffer::Rig::ProviderSetup::TABLE.key?(identifier.to_sym)

    provider_config = config.public_send(identifier)
    values.each { |name, value| provider_config.public_send(:"#{name}=", value) }
  end

  # @rbs identifier: String | Symbol
  # @rbs return: Hash[Symbol, String]?
  def read(identifier)
    @applied[identifier.to_sym]
  end

  # @rbs identifier: String | Symbol
  # @rbs values: Hash[Symbol, String]
  # @rbs setup: Riffer::Rig::ProviderSetup
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: String?
  def store(
    identifier,
    values,
    setup: Riffer::Rig::ProviderSetup.for(identifier),
    auth_path: PATH,
    settings_path: Riffer::Rig::Settings::File::PATH
  )
    secret_names = setup.fields.select(&:secret).map { |field| field.name.to_s }
    fields = values.transform_keys(&:to_s)
    secrets = fields.slice(*secret_names)
    plain = fields.except(*secret_names)

    refusal = (unreadable_settings(settings_path) unless plain.empty?) ||
              AuthFile.store(identifier.to_s, secrets, path: auth_path)
    return refusal if refusal

    ProviderFields.store(identifier.to_s, plain, path: settings_path) unless plain.empty?
  end

  # @rbs identifier: String | Symbol
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: String?
  def remove(identifier, auth_path: PATH, settings_path: Riffer::Rig::Settings::File::PATH)
    unreadable_settings(settings_path) ||
      AuthFile.remove(identifier.to_s, path: auth_path) ||
      ProviderFields.remove(identifier.to_s, path: settings_path)
  end

  # @rbs identifier: String | Symbol
  # @rbs setup: Riffer::Rig::ProviderSetup
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs return: :env | :stored | :chain | :missing | String
  def status(identifier, setup: Riffer::Rig::ProviderSetup.for(identifier), env: Riffer::Rig::Env.new, auth_path: PATH)
    secret_fields = setup.fields.select(&:secret)
    return :env if secret_fields.any? { |field| env.value_for(field) }

    stored = AuthFile.read(identifier.to_s, path: auth_path)
    return stored if stored.is_a?(String)
    return :stored if secret_fields.any? { |field| stored.key?(field.name.to_s) }

    setup.chain ? :chain : :missing
  end

  private

  # @rbs identifier: String | Symbol
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs setup: Riffer::Rig::ProviderSetup
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: (Resolution | String)
  def resolve(identifier, host:, setup:, env:, auth_path:, settings_path:)
    secrets = AuthFile.read(identifier.to_s, path: auth_path)
    return secrets if secrets.is_a?(String)

    plain = ProviderFields.read(identifier.to_s, path: settings_path)
    return plain if plain.is_a?(String)

    found = setup.fields.to_h do |field|
      [field.name, env.value_for(field) || stored_value(field, secrets, plain, env) || field.fallback&.call]
    end.compact
    required = setup.fields.select(&:required)
    answers = ask_for(required.reject { |field| found.key?(field.name) }, identifier, host)
    refusal = store(identifier, answers, setup:, auth_path:, settings_path:)
    return refusal if refusal

    values = found.merge(answers)
    Resolution.new(values:, missing: required.map(&:name) - values.keys)
  end

  # @rbs fields: Array[Riffer::Rig::ProviderSetup::Field]
  # @rbs identifier: String | Symbol
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs return: Hash[Symbol, String]
  def ask_for(fields, identifier, host)
    return {} unless host.capabilities.include?(:ask)

    fields.to_h do |field|
      [field.name, presence(host.ask("#{identifier} #{field.name}", secret: field.secret))]
    end.compact
  end

  # @rbs field: Riffer::Rig::ProviderSetup::Field
  # @rbs secrets: Hash[String, String]
  # @rbs plain: Hash[String, String]
  # @rbs env: Riffer::Rig::Env
  # @rbs return: String?
  def stored_value(field, secrets, plain, env)
    field.secret ? AuthFile.expand(secrets[field.name.to_s], env) : plain[field.name.to_s]
  end

  # @rbs value: String?
  # @rbs return: String?
  def presence(value)
    stripped = value.to_s.strip
    stripped unless stripped.empty?
  end

  # @rbs path: String
  # @rbs return: String?
  def unreadable_settings(path)
    source = Riffer::Rig::Settings::File.read(path)
    source if source.is_a?(String)
  end
end
