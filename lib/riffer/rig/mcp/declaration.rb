# frozen_string_literal: true

class Riffer::Rig::Mcp::Declaration
  include Riffer::Rig::Support::Equatable

  # @dynamic url, headers
  attr_reader :url #: String
  attr_reader :headers #: Hash[String, String]

  # @rbs url: String
  # @rbs headers: Hash[String, String]
  # @rbs return: void
  def initialize(url:, headers:)
    @url = url
    @headers = headers
    freeze
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { url: url, headers: headers }
  end
end
