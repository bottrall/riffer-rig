# frozen_string_literal: true

module Riffer::Rig::Mcp::Auth
  extend self

  PLACEHOLDER = /\$\{(\w+)\}/ #: Regexp

  # @rbs server: String
  # @rbs fields: Hash[Symbol, Array[String]]
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs return: (Hash[Symbol, String] | String)
  def resolve(server, fields, host:, env:, auth_path: Riffer::Rig::Credentials::PATH)
    Riffer::Rig::Credentials.install_values(
      server, host:, env:, auth_path:, label: "MCP server #{server}", setup: setup_for(fields), config: nil
    )
  end

  # @rbs headers: Hash[String, String]
  # @rbs values: Hash[Symbol, String]
  # @rbs return: (Hash[String, String] | String)
  def expand(headers, values)
    undeclared = headers.values.flat_map { |template| undeclared(template, values) }
    return "header references ${#{undeclared.first}}, which the auth block does not declare" if undeclared.any?

    headers.to_h do |name, template|
      [name, template.gsub(PLACEHOLDER) { |token| values.fetch(token.delete_prefix('${').delete_suffix('}').to_sym) }]
    end
  end

  private

  # @rbs template: String
  # @rbs values: Hash[Symbol, String]
  # @rbs return: Array[String]
  def undeclared(template, values)
    template.scan(PLACEHOLDER).flatten.reject { |token| values.key?(token.to_sym) }
  end

  # @rbs fields: Hash[Symbol, Array[String]]
  # @rbs return: Riffer::Rig::ProviderSetup
  def setup_for(fields)
    Riffer::Rig::ProviderSetup.new(
      fields: fields.map do |name, env_names|
        Riffer::Rig::ProviderSetup::Field.new(name:, env: env_names, secret: true, required: true)
      end
    )
  end
end
