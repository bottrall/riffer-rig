# frozen_string_literal: true

class Riffer::Rig::Env
  # @rbs @source: Hash[String, String]

  # @dynamic no_color
  attr_reader :no_color #: bool

  # @rbs source: Hash[String, String]
  # @rbs return: void
  def initialize(source = ENV.to_h)
    @source = source.freeze
    @no_color = @source.key?('NO_COLOR')
    freeze
  end

  # @rbs name: String
  # @rbs return: String?
  def [](name)
    stripped = @source[name].to_s.strip
    stripped unless stripped.empty?
  end

  # @rbs field: Riffer::Rig::ProviderSetup::Field
  # @rbs return: String?
  def value_for(field)
    field.env.filter_map { |name| self[name] }.first
  end
end
