# frozen_string_literal: true

require 'test_helper'
require_relative '../../../fixtures/mcp_https_server'

describe Riffer::Rig::Runtime::McpRegistrar do
  before do
    @server = McpHttpsServer.new
    @ssl_cert_file = ENV.fetch('SSL_CERT_FILE', nil)
    ENV['SSL_CERT_FILE'] = @server.ca_file
    @registrars = []
    @auth_dir = Dir.mktmpdir('rig-mcp-auth')
    @auth_path = File.join(@auth_dir, '.riffer', 'auth.json')
    @host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
  end

  after do
    @registrars.each { |registrar| registrar.retain({}) }
    ENV['SSL_CERT_FILE'] = @ssl_cert_file
    @server.stop
    FileUtils.remove_entry(@auth_dir)
  end

  def registrar(runtime_id = 'one', host: @host, env: {})
    Riffer::Rig::Runtime::McpRegistrar.new(
      runtime_id, registry: Riffer::Mcp, host: host, env: Riffer::Rig::Env.new(env), auth_path: @auth_path
    ).tap { |built| @registrars << built }
  end

  def serving(url: @server.url, headers: {}, auth: {})
    Riffer::Rig::Mcp::Declaration.new(url: url, headers: headers, auth: auth)
  end

  def authed
    serving(headers: { 'X-Token' => 'Bearer ${api_key}' }, auth: { api_key: ['KAGI_API_KEY'] })
  end

  def retained(registrar, declarations)
    registrar.register(declarations).tap { |servers| registrar.retain(servers) }
  end

  def token(servers)
    servers.fetch('web').registration.tools.find { |klass| klass.name == 'web__token' }.new.call(context: nil).content
  end

  def registration(name = 'web')
    Riffer::Mcp.registrations[name]
  end

  def error(message)
    Riffer::Rig::Events::Notify.new(message, :error)
  end

  it 'derives its tag from the Runtime id' do
    assert_equal :riffer_rig_one, registrar('one').tag
  end

  describe '#register' do
    it 'sends the declared headers' do
      assert_equal 'secret', token(retained(registrar, { 'web' => serving(headers: { 'X-Token' => 'secret' }) }))
    end

    it 'sends the auth-resolved headers' do
      built = registrar(env: { 'KAGI_API_KEY' => 'kagi-key' })

      assert_equal 'Bearer kagi-key', token(retained(built, { 'web' => authed }))
    end

    it 'prompts once for a missing credential and sends the answer' do
      host = Class.new(Riffer::Rig::Hosts::Null) do
        define_method(:capabilities) { Set[:ask].freeze }
        define_method(:ask) { |*| 'pasted' }
      end.new

      assert_equal 'Bearer pasted', token(retained(registrar(host: host), { 'web' => authed }))
    end

    it 'reports a server whose credential cannot be resolved through notify' do
      registrar.register({ 'web' => authed })
      notice = 'MCP server web failed to register: MCP server web has no api_key (KAGI_API_KEY); ' \
               'set it in the environment or run riffer interactively to paste it'

      assert_equal [error(notice)], @host.drain
    end

    it 'leaves out a server whose credential cannot be resolved' do
      assert_empty registrar.register({ 'web' => authed })
    end

    it 'reports a header naming an undeclared field through notify' do
      declaration = serving(headers: { 'X-Token' => '${token}' }, auth: { api_key: ['KAGI_API_KEY'] })
      registrar(env: { 'KAGI_API_KEY' => 'kagi-key' }).register({ 'web' => declaration })
      notice = 'MCP server web failed to register: header references ${token}, which the auth block does not declare'

      assert_equal [error(notice)], @host.drain
    end

    it 'keeps the registration of a retained server declared the same' do
      built = registrar
      before = retained(built, { 'web' => serving }).fetch('web')

      assert_same before, built.register({ 'web' => serving }).fetch('web')
    end

    it 'keeps the registration of a retained server whose auth block resolves the same' do
      built = registrar(env: { 'KAGI_API_KEY' => 'kagi-key' })
      before = retained(built, { 'web' => authed }).fetch('web')

      assert_same before, built.register({ 'web' => authed }).fetch('web')
    end

    it 're-registers a server whose url changed' do
      built = registrar
      retained(built, { 'web' => serving })
      before = registration
      retained(built, { 'web' => serving(url: @server.url('alt')) })

      refute_same before, registration
    end

    it 're-registers a server whose headers changed' do
      built = registrar
      retained(built, { 'web' => serving })
      before = registration
      retained(built, { 'web' => serving(headers: { 'X-Token' => 'new' }) })

      refute_same before, registration
    end

    it 'reports a stdio server as unregistrable through notify at error level' do
      registrar.register({ 'local' => Riffer::Rig::Mcp::Declaration.new(command: 'echo') })

      assert_equal [error('MCP server local runs over stdio, which riffer cannot register yet')], @host.drain
    end

    it 'reports a stdio server with auth as unregistrable rather than raising' do
      stdio = Riffer::Rig::Mcp::Declaration.new(command: 'echo', auth: { api_key: ['LOCAL_KEY'] })
      registrar(env: { 'LOCAL_KEY' => 'k' }).register({ 'local' => stdio })

      assert_equal [error('MCP server local runs over stdio, which riffer cannot register yet')], @host.drain
    end

    it 'leaves out a stdio server' do
      assert_empty registrar.register({ 'local' => Riffer::Rig::Mcp::Declaration.new(command: 'echo') })
    end

    it 'returns a server per declaration under its name' do
      servers = retained(registrar, { 'web' => serving, 'alt' => serving(url: @server.url('alt')) })

      assert_equal %w[web alt], servers.keys
    end

    it 'tags each registration with its Runtime' do
      retained(registrar('one'), { 'web' => serving })

      assert_equal [:riffer_rig_one], registration.manifest.tags
    end

    it 'reports a server with a non-HTTPS url through notify' do
      registrar.register({ 'plain' => serving(url: 'http://127.0.0.1/mcp') })

      assert_equal [error('MCP server plain failed to register: MCP manifest endpoint must be a valid HTTPS URL')],
                   @host.drain
    end

    it 'reports a server that cannot be reached through notify' do
      registrar.register({ 'gone' => serving(url: 'https://127.0.0.1:1/mcp') })

      assert_equal [error('MCP server gone failed to register: Internal error handling tools/list request')],
                   @host.drain
    end

    it 'registers the servers around one that fails' do
      servers = retained(registrar, { 'plain' => serving(url: 'http://127.0.0.1/mcp'), 'web' => serving })

      assert_equal %w[web], servers.keys
    end
  end

  describe '#retain' do
    it 'keeps a retained server registered' do
      built = registrar
      servers = retained(built, { 'web' => serving })
      built.retain(servers)

      assert_same servers.fetch('web').registration, registration
    end

    it 'unregisters a server it no longer retains' do
      built = registrar
      retained(built, { 'web' => serving, 'alt' => serving(url: @server.url('alt')) })
      built.retain(built.register({ 'alt' => serving(url: @server.url('alt')) }))

      assert_nil registration
    end

    it 'unregisters every server when it retains none' do
      built = registrar
      retained(built, { 'web' => serving, 'alt' => serving(url: @server.url('alt')) })
      built.retain({})

      assert_empty Riffer::Mcp.registrations.keys & %w[web alt]
    end

    it 'leaves a server another Runtime has since registered under the same name' do
      first = registrar('one')
      retained(first, { 'web' => serving })
      retained(registrar('two'), { 'web' => serving })
      first.retain({})

      assert_equal [:riffer_rig_two], registration.manifest.tags
    end
  end
end
