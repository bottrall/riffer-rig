# frozen_string_literal: true

require 'time'

module Riffer::Rig::Stores::Timestamp
  extend self

  FRACTION_DIGITS = 3 #: Integer

  # @rbs time: Time?
  # @rbs return: String?
  def dump(time)
    time&.getutc&.iso8601(FRACTION_DIGITS)
  end

  # @rbs value: untyped
  # @rbs return: Time?
  def load(value)
    Time.iso8601(value) if value.is_a?(String)
  rescue ArgumentError
    nil
  end
end
