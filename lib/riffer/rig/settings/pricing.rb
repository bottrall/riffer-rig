# frozen_string_literal: true

# USD per million tokens, parsed from a model's entry in the settings file.
class Riffer::Rig::Settings::Pricing
  attr_reader :input, :output, :cache_write, :cache_read #: Float

  # @rbs input: Float
  # @rbs output: Float
  # @rbs cache_write: Float
  # @rbs cache_read: Float
  # @rbs return: void
  def initialize(input:, output:, cache_write:, cache_read:)
    @input = input
    @output = output
    @cache_write = cache_write
    @cache_read = cache_read
  end
end
