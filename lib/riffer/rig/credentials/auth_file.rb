# frozen_string_literal: true

require 'open3'

module Riffer::Rig::Credentials::AuthFile
  extend self

  ENTRY_TYPE = 'api_key'

  # @rbs identifier: String
  # @rbs path: String
  # @rbs return: (Hash[String, String] | String)
  def read(identifier, path:)
    document = Riffer::Rig::Support::JsonFile.read(path)
    return document if document.is_a?(String)

    entry = document[identifier]
    api_key_entry?(entry) ? entry.except('type').select { |_name, value| value.is_a?(String) } : {}
  end

  # @rbs identifier: String
  # @rbs secrets: Hash[String, String]
  # @rbs path: String
  # @rbs return: String?
  def store(identifier, secrets, path:)
    return nil if secrets.empty?

    update(path) do |document|
      stored = document[identifier]
      entry = (api_key_entry?(stored) ? stored : { 'type' => ENTRY_TYPE }).merge(secrets)
      document.merge(identifier => entry)
    end
  end

  # @rbs identifier: String
  # @rbs path: String
  # @rbs return: String?
  def remove(identifier, path:)
    update(path) { |document| document.except(identifier) }
  end

  # @rbs value: String?
  # @rbs env: Riffer::Rig::Env
  # @rbs return: String?
  def expand(value, env)
    return nil if value.nil?
    return env[value.delete_prefix('$')] if value.start_with?('$')
    return run(value.delete_prefix('!')) if value.start_with?('!')

    value
  end

  private

  # @rbs command: String
  # @rbs return: String?
  def run(command)
    stdout, status = Open3.capture2(command)
    output = stdout.strip
    output if status.success? && !output.empty?
  end

  # @rbs entry: untyped
  # @rbs return: bool
  def api_key_entry?(entry)
    entry.is_a?(Hash) && entry['type'] == ENTRY_TYPE
  end

  # @rbs path: String
  # @rbs &: (Hash[untyped, untyped]) -> Hash[untyped, untyped]
  # @rbs return: String?
  def update(path, &)
    Riffer::Rig::Support::JsonFile.update(path, mode: 0o600, &)
  end
end
