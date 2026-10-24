# frozen_string_literal: true

module Riffer::Rig::ACP::Servers
  extend self

  # @rbs servers: Array[::ACP::Types::McpServer::t]
  # @rbs return: Hash[String, Riffer::Rig::Mcp::Declaration]
  def declarations(servers)
    servers.filter_map { |server| declaration_of(server) }.to_h
  end

  # @rbs servers: Array[::ACP::Types::McpServer::t]
  # @rbs return: Array[String]
  def warnings(servers)
    servers.filter_map do |server|
      next if server.is_a?(::ACP::Types::McpServerStdio)

      "Skipped MCP server #{name_of(server)}: only stdio servers are supported"
    end
  end

  private

  # @rbs server: ::ACP::Types::McpServer::t
  # @rbs return: [String, Riffer::Rig::Mcp::Declaration]?
  def declaration_of(server)
    return unless server.is_a?(::ACP::Types::McpServerStdio)

    [
      server.name,
      Riffer::Rig::Mcp::Declaration.new(
        command: server.command, args: server.args, env: server.env.to_h { |variable| [variable.name, variable.value] }
      )
    ]
  end

  # @rbs server: ::ACP::Types::McpServer::t
  # @rbs return: String
  def name_of(server)
    server.is_a?(Hash) ? server['name'].to_s : server.name
  end
end
