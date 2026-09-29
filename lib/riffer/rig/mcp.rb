# frozen_string_literal: true

module Riffer::Rig::Mcp
  # @rbs!
  #   type declaration = { url: String, headers: Hash[String, String] }
  #   type server = { declaration: declaration, registration: Riffer::Mcp::Registration }
  #
  #   interface _Registry
  #     def register: (Hash[Symbol, untyped]) -> Riffer::Mcp::Registration
  #     def unregister: (String) -> void
  #   end

  extend self

  # @rbs home: Hash[Symbol, untyped]
  # @rbs project: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped]
  def merge(home, project)
    home.merge(project, servers: home[:servers].to_h.merge(project[:servers].to_h))
  end
end
