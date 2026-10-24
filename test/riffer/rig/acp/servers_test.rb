# frozen_string_literal: true

require 'test_helper'
require 'acp/sdk'

describe Riffer::Rig::ACP::Servers do
  def stdio(name)
    ACP::Types::McpServer.from_h(
      'name' => name, 'command' => '/bin/stub', 'args' => ['--flag'], 'env' => [{ 'name' => 'TOKEN', 'value' => 't' }]
    )
  end

  def http(name)
    ACP::Types::McpServer.from_h('name' => name, 'type' => 'http', 'url' => 'https://docs.example/mcp', 'headers' => [])
  end

  describe '.declarations' do
    it 'declares a stdio server under its name' do
      declaration = Riffer::Rig::Mcp::Declaration.new(command: '/bin/stub', args: ['--flag'], env: { 'TOKEN' => 't' })

      assert_equal({ 'stub' => declaration }, Riffer::Rig::ACP::Servers.declarations([stdio('stub')]))
    end

    it 'declares no server of another shape' do
      assert_empty Riffer::Rig::ACP::Servers.declarations([http('httpdocs')])
    end
  end

  describe '.warnings' do
    it 'warns about nothing for a stdio server' do
      assert_empty Riffer::Rig::ACP::Servers.warnings([stdio('stub')])
    end

    it 'names a skipped http server' do
      assert_equal ['Skipped MCP server httpdocs: only stdio servers are supported'],
                   Riffer::Rig::ACP::Servers.warnings([http('httpdocs')])
    end

    it 'names a skipped sse server' do
      server = ACP::Types::McpServer.from_h(
        'name' => 'ssedocs', 'type' => 'sse', 'url' => 'https://docs.example/sse', 'headers' => []
      )

      assert_equal ['Skipped MCP server ssedocs: only stdio servers are supported'],
                   Riffer::Rig::ACP::Servers.warnings([server])
    end

    it 'names a skipped server of an unknown type' do
      server = ACP::Types::McpServer.from_h('name' => 'odd', 'type' => 'websocket')

      assert_equal ['Skipped MCP server odd: only stdio servers are supported'],
                   Riffer::Rig::ACP::Servers.warnings([server])
    end
  end
end
