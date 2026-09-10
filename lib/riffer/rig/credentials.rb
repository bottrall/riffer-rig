# frozen_string_literal: true

require 'json'
require 'fileutils'

# Reads and writes API keys for each supported provider in
# <tt>~/.riffer/auth.json</tt>.
#
# Keys are stored under the provider name, e.g.:
#
#   {
#     "anthropic": "sk-ant-...",
#     "openai": "sk-...",
#     "gemini": "...",
#     "openrouter": "sk-or-..."
#   }
#
# The environment variable checked per provider:
#
#   anthropic  → ANTHROPIC_API_KEY
#   openai     → OPENAI_API_KEY
#   gemini     → GEMINI_API_KEY
#   openrouter → OPENROUTER_API_KEY
#
module Riffer::Rig::Credentials
  extend self

  PATH = File.expand_path('~/.riffer/auth.json') #: String

  PROVIDER_ENV_VARS = {
    'anthropic' => 'ANTHROPIC_API_KEY',
    'openai' => 'OPENAI_API_KEY',
    'gemini' => 'GEMINI_API_KEY',
    'openrouter' => 'OPENROUTER_API_KEY'
  }.freeze #: Hash[String, String]

  # Returns the API key for +provider+, checking the environment variable first,
  # then the stored file. Returns +nil+ if no key is available.
  #
  # @rbs provider: String?
  # @rbs path: String
  # @rbs return: String?
  def api_key_for(provider, path: PATH)
    env_var = provider && PROVIDER_ENV_VARS[provider]
    key = env_var && ENV.fetch(env_var, nil).then { |v| v unless v.nil? || v.strip.empty? }
    key || key_from_file(provider, path)
  end

  # Saves an API key for +provider+ to the auth file with 0600 permissions.
  #
  # @rbs provider: String
  # @rbs key: String
  # @rbs path: String
  # @rbs return: String
  def save_api_key(provider, key, path: PATH)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    data = read(path).tap { |h| h[provider] = key }
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
    return nil unless key.is_a?(String)
    return key unless key.strip.empty?

    nil
  end

  # The parsed auth file, or an empty hash when the file is absent or
  # malformed.
  #
  # @rbs path: String
  # @rbs return: Hash[String, untyped]
  def read(path)
    return {} unless File.file?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError
    {}
  end
end
