# frozen_string_literal: true

# Holds a model's prices in USD per million tokens.
class Riffer::Rig::Settings::Pricing
  # @dynamic input, output, cache_write, cache_read
  attr_reader :input, :output, :cache_write, :cache_read #: Float

  # Builds a Pricing from a settings-file entry, pricing missing keys at zero.
  #
  # @rbs entry: Hash[String, untyped]
  # @rbs return: ::Riffer::Rig::Settings::Pricing
  def self.from(entry)
    new(
      input: entry.fetch('input', 0).to_f,
      output: entry.fetch('output', 0).to_f,
      cache_write: entry.fetch('cache_write', 0).to_f,
      cache_read: entry.fetch('cache_read', 0).to_f
    )
  end

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
