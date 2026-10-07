# frozen_string_literal: true

module Riffer::Rig::Mcp::Auth
  extend self

  class Error < StandardError; end

  PLACEHOLDER = /\$\{(\w+)\}/ #: Regexp

  # @rbs server: String
  # @rbs fields: Hash[Symbol, Array[String]]
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs return: Hash[Symbol, String]
  def resolve(server, fields, host:, env:, auth_path: Riffer::Rig::Credentials::PATH)
    setup = setup_for(fields)
    resolution = Riffer::Rig::Credentials.resolve(server, host:, setup:, env:, auth_path:)
    unless resolution.missing.empty?
      raise Error,
            "MCP server #{server} has no #{setup.missing_fields(resolution.missing)}; " \
            'set it in the environment or run riffer interactively to paste it'
    end

    resolution.values
  end

  # @rbs headers: Hash[String, String]
  # @rbs values: Hash[Symbol, String]
  # @rbs return: Hash[String, String]
  def expand(headers, values)
    headers.each_value { |template| check(template, values) }
    headers.to_h do |name, template|
      [name, template.gsub(PLACEHOLDER) { |token| values.fetch(token.delete_prefix('${').delete_suffix('}').to_sym) }]
    end
  end

  private

  # @rbs template: String
  # @rbs values: Hash[Symbol, String]
  # @rbs return: void
  def check(template, values)
    undeclared = template.scan(PLACEHOLDER).flatten.reject { |token| values.key?(token.to_sym) }
    return if undeclared.empty?

    raise Error, "header references ${#{undeclared.first}}, which the auth block does not declare"
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
