# frozen_string_literal: true

class Riffer::Rig::Mcp::Declaration
  include Riffer::Rig::Support::Equatable

  # @dynamic url, headers, auth, command, args, env
  attr_reader :url #: String?
  attr_reader :headers #: Hash[String, String]
  attr_reader :auth #: Hash[Symbol, Array[String]]
  attr_reader :command #: String?
  attr_reader :args #: Array[String]
  attr_reader :env #: Hash[String, String]

  # A declaration is one server over one transport: HTTPS by url, or stdio by
  # command. Raising is a programmer error: the registrar seam refuses an
  # empty declaration before the Runtime ever sees it.
  # @rbs url: String?
  # @rbs headers: Hash[String, String]
  # @rbs auth: Hash[Symbol, Array[String]]
  # @rbs command: String?
  # @rbs args: Array[String]
  # @rbs env: Hash[String, String]
  # @rbs return: void
  def initialize(url: nil, headers: {}, auth: {}, command: nil, args: [], env: {})
    raise ArgumentError, 'a declaration takes a url or a command, not both' if url && command
    raise ArgumentError, 'a declaration takes a url or a command' unless url || command

    @url = url
    @headers = headers
    @auth = auth
    @command = command
    @args = args
    @env = env
    freeze
  end

  # @rbs headers: Hash[String, String]
  # @rbs return: Riffer::Rig::Mcp::Declaration
  def with_headers(headers)
    self.class.new(url: url, headers: headers, auth: auth)
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { url: url, headers: headers, auth: auth, command: command, args: args, env: env }
  end
end
