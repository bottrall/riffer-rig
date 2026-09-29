# frozen_string_literal: true

module Riffer::Rig::Mcp
  extend self

  # @rbs home: Hash[Symbol, untyped]
  # @rbs project: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped]
  def merge(home, project)
    home.merge(project, servers: home[:servers].to_h.merge(project[:servers].to_h))
  end
end
