# frozen_string_literal: true

class Riffer::Rig::Trust::Decision
  include Riffer::Rig::Support::Equatable

  # @dynamic sha256, trusted
  attr_reader :sha256 #: String
  attr_reader :trusted #: bool

  # @rbs sha256: String
  # @rbs trusted: bool
  # @rbs return: void
  def initialize(sha256:, trusted:)
    @sha256 = sha256
    @trusted = trusted
    freeze
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { sha256: sha256, trusted: trusted }
  end
end
