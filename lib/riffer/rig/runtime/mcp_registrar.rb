# frozen_string_literal: true

class Riffer::Rig::Runtime::McpRegistrar
  # @rbs @registry: Riffer::Rig::Mcp::_Registry
  # @rbs @host: Riffer::Rig::Hosts::_Host
  # @rbs @env: Riffer::Rig::Env
  # @rbs @auth_path: String
  # @rbs @servers: Hash[String, Riffer::Rig::Mcp::Server]

  # @dynamic tag
  attr_reader :tag #: Symbol

  # @rbs runtime_id: String
  # @rbs registry: Riffer::Rig::Mcp::_Registry
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs return: void
  def initialize(runtime_id, registry:, host:, env:, auth_path:)
    # Upstream candidate: riffer's MCP registry is process-wide and keyed by
    # server name alone, so each Runtime tags its registrations, and two
    # Runtimes declaring the same name replace each other's.
    @tag = :"riffer_rig_#{runtime_id}"
    @registry = registry
    @host = host
    @env = env
    @auth_path = auth_path
    @servers = {}
  end

  # @rbs declarations: Hash[String, Riffer::Rig::Mcp::Declaration]
  # @rbs return: Hash[String, Riffer::Rig::Mcp::Server]
  def register(declarations)
    declarations.filter_map do |name, declaration|
      resolved = resolve(name, declaration)
      next nil unless resolved

      live = @servers[name]
      server = live && live.declaration == resolved ? live : register_server(name, resolved)
      [name, server] if server
    end.to_h
  end

  # @rbs servers: Hash[String, Riffer::Rig::Mcp::Server]
  # @rbs return: void
  def retain(servers)
    dropped = @servers.except(*servers.keys)
    @servers = servers
    # A retired registration was replaced under the same name, by another
    # Runtime or a later declaration, and is no longer this Runtime's to remove.
    dropped.each { |name, server| @registry.unregister(name) unless server.registration.retired? }
  end

  private

  # The stored declaration is the resolved one, so a later register compares
  # resolved headers and re-registers when the credentials changed.
  # @rbs name: String
  # @rbs declaration: Riffer::Rig::Mcp::Declaration
  # @rbs return: Riffer::Rig::Mcp::Declaration?
  def resolve(name, declaration)
    return declaration if declaration.auth.empty?

    values = Riffer::Rig::Mcp::Auth.resolve(name, declaration.auth, host: @host, env: @env, auth_path: @auth_path)
    declaration.with_headers(Riffer::Rig::Mcp::Auth.expand(declaration.headers, values))
  rescue Riffer::Rig::Mcp::Auth::Error => e
    @host.notify("MCP server #{name} failed to register: #{e.message}", level: :error)
    nil
  end

  # @rbs name: String
  # @rbs declaration: Riffer::Rig::Mcp::Declaration
  # @rbs return: Riffer::Rig::Mcp::Server?
  def register_server(name, declaration)
    unless declaration.url
      # Upstream candidate: riffer's MCP registry speaks HTTPS only, so a
      # stdio declaration reaches the Runtime but cannot be registered until
      # riffer grows a stdio client.
      @host.notify("MCP server #{name} runs over stdio, which riffer cannot register yet", level: :error)
      return nil
    end

    registration = @registry.register(
      name: name, endpoint: declaration.url, tags: [@tag], discovery_headers: declaration.headers
    )
    Riffer::Rig::Mcp::Server.new(declaration: declaration, registration: registration)
  rescue StandardError => e
    @host.notify("MCP server #{name} failed to register: #{e.message}", level: :error)
    nil
  end
end
