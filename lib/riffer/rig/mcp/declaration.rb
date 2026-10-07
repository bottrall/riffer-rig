# frozen_string_literal: true

class Riffer::Rig::Mcp::Declaration
  include Riffer::Rig::Support::Equatable

  # @dynamic url, headers, auth
  attr_reader :url #: String
  attr_reader :headers #: Hash[String, String]
  attr_reader :auth #: Hash[Symbol, Array[String]]

  # @rbs url: String
  # @rbs headers: Hash[String, String]
  # @rbs auth: Hash[Symbol, Array[String]]
  # @rbs return: void
  def initialize(url:, headers:, auth: {})
    @url = url
    @headers = headers
    @auth = auth
    freeze
  end

  # @rbs headers: Hash[String, String]
  # @rbs return: Riffer::Rig::Mcp::Declaration
  def with_headers(headers)
    self.class.new(url: url, headers: headers, auth: auth)
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { url: url, headers: headers, auth: auth }
  end
end
