# frozen_string_literal: true

class Riffer::Rig::Mcp::Server
  # @dynamic declaration, registration
  attr_reader :declaration #: Riffer::Rig::Mcp::Declaration
  attr_reader :registration #: Riffer::Mcp::Registration

  # @rbs declaration: Riffer::Rig::Mcp::Declaration
  # @rbs registration: Riffer::Mcp::Registration
  # @rbs return: void
  def initialize(declaration:, registration:)
    @declaration = declaration
    @registration = registration
    freeze
  end
end
