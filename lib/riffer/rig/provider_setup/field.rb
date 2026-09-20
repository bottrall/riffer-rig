# frozen_string_literal: true

class Riffer::Rig::ProviderSetup::Field
  # @dynamic name, env, secret, required, fallback
  attr_reader :name #: Symbol
  attr_reader :env #: Array[String]
  attr_reader :secret, :required #: bool
  attr_reader :fallback #: (^() -> String?)?

  # @rbs name: Symbol
  # @rbs env: Array[String]
  # @rbs secret: bool
  # @rbs required: bool
  # @rbs fallback: (^() -> String?)?
  # @rbs return: void
  def initialize(name:, env:, secret:, required:, fallback: nil)
    @name = name
    @env = env.freeze
    @secret = secret
    @required = required
    @fallback = fallback
    freeze
  end
end
