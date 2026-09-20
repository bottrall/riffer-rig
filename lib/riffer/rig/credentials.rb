# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'open3'

module Riffer::Rig::Credentials
  extend self

  # @rbs!
  #   interface _Env
  #     def []: (String) -> String?
  #   end

  PATH = File.expand_path('~/.riffer/auth.json') #: String

  ENTRY_TYPE = 'api_key'

  # @rbs identifier: String | Symbol
  # @rbs host: Riffer::Rig::Hosts::Base
  # @rbs setup: Riffer::Rig::ProviderSetup
  # @rbs env: _Env
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: Resolution
  def resolve(
    identifier,
    host:,
    setup: Riffer::Rig::ProviderSetup.for(identifier),
    env: ENV,
    auth_path: PATH,
    settings_path: Riffer::Rig::Settings::PATH
  )
    secrets = stored_secrets(identifier, auth_path)
    plain = Riffer::Rig::Settings.provider_fields(identifier.to_s, path: settings_path)
    found = setup.fields.to_h do |field|
      [field.name, from_env(field, env) || stored_value(field, secrets, plain, env) || field.fallback&.call]
    end.compact
    required = setup.fields.select(&:required)
    answers = ask_for(required.reject { |field| found.key?(field.name) }, identifier, host)
    store(identifier, answers, setup:, auth_path:, settings_path:)

    values = found.merge(answers)
    Resolution.new(values:, missing: required.map(&:name) - values.keys)
  end

  # @rbs identifier: String | Symbol
  # @rbs values: Hash[Symbol, String]
  # @rbs config: Riffer::Config
  # @rbs return: void
  def apply(identifier, values, config: Riffer.config)
    return unless Riffer::Rig::ProviderSetup[identifier]

    provider_config = config.public_send(identifier)
    values.each { |name, value| provider_config[name] = value }
  end

  # @rbs identifier: String | Symbol
  # @rbs values: Hash[Symbol, String]
  # @rbs setup: Riffer::Rig::ProviderSetup
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: void
  def store(
    identifier,
    values,
    setup: Riffer::Rig::ProviderSetup.for(identifier),
    auth_path: PATH,
    settings_path: Riffer::Rig::Settings::PATH
  )
    secret_names = setup.fields.select(&:secret).map { |field| field.name.to_s }
    fields = values.transform_keys(&:to_s)
    secrets = fields.slice(*secret_names)
    plain = fields.except(*secret_names)

    unless secrets.empty?
      entries = read_auth(auth_path).merge(identifier.to_s => secrets) do |_identifier, stored, given|
        stored.merge(given)
      end
      write_auth(auth_path, entries)
    end
    Riffer::Rig::Settings.store_provider(identifier.to_s, plain, path: settings_path) unless plain.empty?
  end

  # @rbs identifier: String | Symbol
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: void
  def remove(identifier, auth_path: PATH, settings_path: Riffer::Rig::Settings::PATH)
    entries = read_auth(auth_path)
    write_auth(auth_path, entries.except(identifier.to_s)) if entries.key?(identifier.to_s)
    Riffer::Rig::Settings.remove_provider(identifier.to_s, path: settings_path)
  end

  # @rbs identifier: String | Symbol
  # @rbs setup: Riffer::Rig::ProviderSetup
  # @rbs env: _Env
  # @rbs auth_path: String
  # @rbs return: :env | :stored | :chain | :missing
  def status(identifier, setup: Riffer::Rig::ProviderSetup.for(identifier), env: ENV, auth_path: PATH)
    secret_fields = setup.fields.select(&:secret)
    return :env if secret_fields.any? { |field| from_env(field, env) }

    stored = stored_secrets(identifier, auth_path)
    return :stored if secret_fields.any? { |field| stored.key?(field.name.to_s) }

    setup.chain ? :chain : :missing
  end

  private

  # @rbs fields: Array[Riffer::Rig::ProviderSetup::Field]
  # @rbs identifier: String | Symbol
  # @rbs host: Riffer::Rig::Hosts::Base
  # @rbs return: Hash[Symbol, String]
  def ask_for(fields, identifier, host)
    fields.to_h do |field|
      [field.name, presence(host.ask("#{identifier} #{field.name}", secret: field.secret))]
    end.compact
  end

  # @rbs field: Riffer::Rig::ProviderSetup::Field
  # @rbs env: _Env
  # @rbs return: String?
  def from_env(field, env)
    field.env.filter_map { |name| presence(env[name]) }.first
  end

  # @rbs field: Riffer::Rig::ProviderSetup::Field
  # @rbs secrets: Hash[String, String]
  # @rbs plain: Hash[String, String]
  # @rbs env: _Env
  # @rbs return: String?
  def stored_value(field, secrets, plain, env)
    field.secret ? expand(secrets[field.name.to_s], env) : plain[field.name.to_s]
  end

  # @rbs value: String?
  # @rbs env: _Env
  # @rbs return: String?
  def expand(value, env)
    return nil if value.nil?
    return presence(env[value.delete_prefix('$')]) if value.start_with?('$')
    return presence(run(value.delete_prefix('!'))) if value.start_with?('!')

    value
  end

  # @rbs command: String
  # @rbs return: String?
  def run(command)
    stdout, status = Open3.capture2(command)
    stdout if status.success?
  end

  # @rbs value: String?
  # @rbs return: String?
  def presence(value)
    stripped = value.to_s.strip
    stripped unless stripped.empty?
  end

  # @rbs identifier: String | Symbol
  # @rbs path: String
  # @rbs return: Hash[String, String]
  def stored_secrets(identifier, path)
    read_auth(path)[identifier.to_s] || {}
  end

  # @rbs path: String
  # @rbs return: Hash[String, Hash[String, String]]
  def read_auth(path)
    return {} unless File.file?(path)

    JSON.parse(File.read(path))
        .select { |_identifier, entry| entry.is_a?(Hash) && entry['type'] == ENTRY_TYPE }
        .transform_values { |entry| entry.except('type').select { |_name, value| value.is_a?(String) } }
  rescue JSON::ParserError
    {}
  end

  # @rbs path: String
  # @rbs entries: Hash[String, Hash[String, String]]
  # @rbs return: void
  def write_auth(path, entries)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    data = entries.transform_values { |fields| { 'type' => ENTRY_TYPE }.merge(fields) }
    File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
      file.write(JSON.pretty_generate(data))
    end
  end
end
