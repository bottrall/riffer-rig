# frozen_string_literal: true

module Riffer::Rig::Settings
  extend self

  # MCP servers merge by name, whole, so a home server's headers never reach a
  # project server's url.
  # @rbs home: Hash[Symbol, untyped]
  # @rbs project: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped]
  def merge(home, project)
    merged = deep_merge(home, project)
    home_mcp = home[:mcp]
    project_mcp = project[:mcp]
    if home_mcp.is_a?(Hash) && project_mcp.is_a?(Hash)
      merged = merged.merge(mcp: Riffer::Rig::Mcp.merge(home_mcp, project_mcp))
    end
    disabled = [home, project].flat_map { |scope| Document.new(scope).disabled }.uniq
    return merged if disabled.empty?

    extensions = merged[:extensions].is_a?(Hash) ? merged[:extensions] : {} #: Hash[Symbol, untyped]
    merged.merge(extensions: extensions.merge(disabled: disabled))
  end

  private

  # @rbs home: Hash[Symbol, untyped]
  # @rbs project: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped]
  def deep_merge(home, project)
    home.merge(project) do |_key, earlier, later|
      earlier.is_a?(Hash) && later.is_a?(Hash) ? deep_merge(earlier, later) : later
    end
  end
end
