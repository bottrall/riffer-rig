# frozen_string_literal: true

class Riffer::Rig::Env
  # @rbs @source: Hash[String, String]

  # @dynamic no_color, model
  attr_reader :no_color #: bool
  attr_reader :model #: String?

  # @rbs source: Hash[String, String]
  # @rbs return: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  def self.load(source = ENV.to_h)
    env = new(source)
    model = env.model
    rejection = model && Riffer::Rig::Settings.rejection(model)
    rejection ? Invalid.new("RIFFER_MODEL: #{rejection}") : env
  end

  # @rbs source: Hash[String, String]
  # @rbs return: void
  def initialize(source = ENV.to_h)
    @source = source.freeze
    @no_color = @source.key?('NO_COLOR')
    @model = self['RIFFER_MODEL']
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
