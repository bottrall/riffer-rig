# frozen_string_literal: true

require 'json'
require 'fileutils'

module Riffer::Rig::Credentials
  extend self

  PATH = File.expand_path('~/.riffer/auth.json') #: String

  PROVIDER_ENV_VARS = {
    'anthropic' => 'ANTHROPIC_API_KEY',
    'openai' => 'OPENAI_API_KEY',
    'gemini' => 'GEMINI_API_KEY',
    'openrouter' => 'OPENROUTER_API_KEY'
  }.freeze #: Hash[String, String]

  # @rbs provider: String?
  # @rbs path: String
  # @rbs return: String?
  def api_key_for(provider, path: PATH)
    env_var = provider && PROVIDER_ENV_VARS[provider]
    key = env_var && ENV.fetch(env_var, nil).then { |v| v unless v.nil? || v.strip.empty? }
    key || key_from_file(provider, path)
  end

  # @rbs provider: String
  # @rbs key: String
  # @rbs path: String
  # @rbs return: String
  def save_api_key(provider, key, path: PATH)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    data = read(path).merge(provider => key)
    File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
      file.write(JSON.pretty_generate(data))
    end
    key
  end

  private

  # @rbs provider: String?
  # @rbs path: String
  # @rbs return: String?
  def key_from_file(provider, path)
    key = read(path)[provider]
    return nil if key.nil? || key.strip.empty?

    key
  end

  # @rbs path: String
  # @rbs return: Hash[String, String]
  def read(path)
    return {} unless File.file?(path)

    JSON.parse(File.read(path)).select { |_provider, key| key.is_a?(String) }
  rescue JSON::ParserError
    {}
  end
end
