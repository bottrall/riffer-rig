# frozen_string_literal: true

require 'test_helper'
require 'fileutils'
require 'json'

class PromptingHost
  attr_reader :asked #: Array[String]

  # @rbs answer: String
  # @rbs return: void
  def initialize(answer)
    @answer = answer
    @asked = []
  end

  # @rbs return: Set[Symbol]
  def capabilities
    Set.new
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question = nil, options: nil, secret: false)
    @asked << question.to_s
    @answer
  end

  # @rbs question: String?
  # @rbs return: bool
  def confirm(_question = nil)
    false
  end

  # @rbs message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message = nil, level: :info)
    Riffer::Rig::Hosts::Null.new.notify(message, level: level)
  end

  # @rbs label: String?
  # @rbs &block: ? () -> void
  # @rbs return: void
  def progress(_label = nil, &block)
    block&.call
  end
end

describe Riffer::Rig::Mcp::Auth do
  let(:null_host) { Riffer::Rig::Hosts::Null.new }

  def in_tmp_home
    Dir.mktmpdir do |dir|
      yield File.join(dir, '.riffer', 'auth.json')
    end
  end

  def store_secret(auth_path, server, fields)
    FileUtils.mkdir_p(File.dirname(auth_path))
    File.write(auth_path, JSON.pretty_generate(server => { 'type' => 'api_key' }.merge(fields)))
  end

  def stored_fields(auth_path, server)
    JSON.parse(File.read(auth_path)).fetch(server).except('type')
  end

  describe '.resolve' do
    it 'prefers the env var over the stored value' do
      in_tmp_home do |auth_path|
        store_secret(auth_path, 'docs', 'api_key' => 'stored')

        values = Riffer::Rig::Mcp::Auth.resolve(
          'docs',
          { api_key: ['DOCS_API_KEY'] },
          host: null_host,
          env: env('DOCS_API_KEY' => 'from-env'),
          auth_path:
        )

        assert_equal({ api_key: 'from-env' }, values)
      end
    end

    it 'uses the stored value when the env var is unset' do
      in_tmp_home do |auth_path|
        store_secret(auth_path, 'docs', 'api_key' => 'stored')

        values = Riffer::Rig::Mcp::Auth.resolve(
          'docs', { api_key: ['DOCS_API_KEY'] }, host: null_host, env: env, auth_path:
        )

        assert_equal({ api_key: 'stored' }, values)
      end
    end

    it 'prompts for a missing field and returns the answer' do
      in_tmp_home do |auth_path|
        values = Riffer::Rig::Mcp::Auth.resolve(
          'docs', { api_key: ['DOCS_API_KEY'] }, host: PromptingHost.new('pasted'), env: env, auth_path:
        )

        assert_equal({ api_key: 'pasted' }, values)
      end
    end

    it 'stores the prompted answer under the server name' do
      in_tmp_home do |auth_path|
        Riffer::Rig::Mcp::Auth.resolve(
          'docs', { api_key: ['DOCS_API_KEY'] }, host: PromptingHost.new('pasted'), env: env, auth_path:
        )

        assert_equal({ 'api_key' => 'pasted' }, stored_fields(auth_path, 'docs'))
      end
    end

    it 'does not prompt again once the field is stored' do
      in_tmp_home do |auth_path|
        Riffer::Rig::Mcp::Auth.resolve(
          'docs', { api_key: ['DOCS_API_KEY'] }, host: PromptingHost.new('pasted'), env: env, auth_path:
        )
        host = PromptingHost.new('again')

        Riffer::Rig::Mcp::Auth.resolve('docs', { api_key: ['DOCS_API_KEY'] }, host:, env: env, auth_path:)

        assert_empty host.asked
      end
    end

    it 'raises with the env var names when the field cannot be resolved' do
      in_tmp_home do |auth_path|
        error = assert_raises(Riffer::Rig::Mcp::Auth::Error) do
          Riffer::Rig::Mcp::Auth.resolve(
            'docs', { api_key: %w[DOCS_API_KEY DOCS_TOKEN] }, host: null_host, env: env, auth_path:
          )
        end

        assert_equal(
          'MCP server docs has no api_key (DOCS_API_KEY or DOCS_TOKEN); ' \
          'set it in the environment or run riffer interactively to paste it',
          error.message
        )
      end
    end
  end

  describe '.expand' do
    it 'substitutes every declared field into the headers' do
      headers = { 'Authorization' => 'Bearer ${api_key}', 'X-Org' => '${org}' }

      assert_equal(
        { 'Authorization' => 'Bearer secret', 'X-Org' => 'acme' },
        Riffer::Rig::Mcp::Auth.expand(headers, { api_key: 'secret', org: 'acme' })
      )
    end

    it 'keeps text without placeholders as written' do
      assert_equal({ 'X-Token' => 'plain' }, Riffer::Rig::Mcp::Auth.expand({ 'X-Token' => 'plain' }, {}))
    end

    it 'raises when a placeholder is not an auth field' do
      error = assert_raises(Riffer::Rig::Mcp::Auth::Error) do
        Riffer::Rig::Mcp::Auth.expand({ 'Authorization' => 'Bearer ${token}' }, { api_key: 'secret' })
      end

      assert_equal 'header references ${token}, which the auth block does not declare', error.message
    end
  end

  private

  # @rbs source: Hash[String, String]
  # @rbs return: Riffer::Rig::Env
  def env(source = {})
    Riffer::Rig::Env.new(source)
  end
end
