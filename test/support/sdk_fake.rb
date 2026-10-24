# frozen_string_literal: true

class SdkFake
  attr_reader :ensured #: Array[[String, String]]

  # @rbs message: String?
  # @rbs return: void
  def initialize(message = nil)
    @message = message
    @ensured = []
  end

  # @rbs gem: String
  # @rbs requirement: String
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs return: String?
  def ensure(gem, requirement, host:)
    @ensured << [gem, requirement]
    @message
  end
end
