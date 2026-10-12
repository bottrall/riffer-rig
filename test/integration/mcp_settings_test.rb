# frozen_string_literal: true

require 'test_helper'
require_relative '../fixtures/mcp_https_server'

describe 'MCP servers declared in the mcp settings' do
  before do
    @server = McpHttpsServer.new
    @ssl_cert_file = ENV.fetch('SSL_CERT_FILE', nil)
    ENV['SSL_CERT_FILE'] = @server.ca_file
    @runtimes = []
    @auth_dir = Dir.mktmpdir('rig-mcp-auth')
    @auth_path = File.join(@auth_dir, '.riffer', 'auth.json')
  end

  after do
    @runtimes.each(&:close)
    ENV['SSL_CERT_FILE'] = @ssl_cert_file
    @server.stop
    FileUtils.remove_entry(@auth_dir)
  end

  def runtime(servers, env: {})
    Riffer::Rig::Runtime.new(
      'mock/test',
      extensions: [Riffer::Rig.bundled(:mcp)],
      settings: { mcp: { servers: servers } },
      env: Riffer::Rig::Env.new(env),
      auth_path: @auth_path
    ).tap { |built| @runtimes << built }
  end

  it 'gives the agent the tools of each declared server' do
    assert_equal %w[web__echo web__token], runtime({ web: { url: @server.url } }).agent.tools.map(&:name)
  end

  it 'sends the headers its auth block resolves from the environment' do
    web = { url: @server.url, auth: { api_key: 'KAGI_API_KEY' }, headers: { 'X-Token' => 'Bearer ${api_key}' } }
    tools = runtime({ web: web }, env: { 'KAGI_API_KEY' => 'kagi-key' }).agent.tools

    assert_equal 'Bearer kagi-key', tools.find { |klass| klass.name == 'web__token' }.new.call(context: nil).content
  end
end
