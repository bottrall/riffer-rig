# frozen_string_literal: true

class Riffer::Rig::Settings::Document
  # @rbs @model: String?
  # @rbs @reasoning: String?
  # @rbs @models: Hash[String, Riffer::Rig::Settings::Pricing]
  # @rbs @providers: Hash[String, Hash[String, String]]

  # @dynamic model, reasoning, models, providers
  attr_reader :model #: String?
  attr_reader :reasoning #: String?
  attr_reader :models #: Hash[String, Riffer::Rig::Settings::Pricing]
  attr_reader :providers #: Hash[String, Hash[String, String]]

  # @rbs source: untyped
  # @rbs return: void
  def initialize(source)
    @model = source['model'].is_a?(String) ? source['model'] : nil
    @reasoning = source['reasoning'].is_a?(String) ? source['reasoning'] : nil
    entries = source['models'].is_a?(Hash) ? source['models'] : {} #: Hash[String, untyped]
    @models = entries.filter_map do |name, entry|
      [name, Riffer::Rig::Settings::Pricing.from(entry)] if name.is_a?(String) && entry.is_a?(Hash)
    end.to_h
    blocks = source['providers'].is_a?(Hash) ? source['providers'] : {} #: Hash[String, untyped]
    @providers = blocks.select { |_identifier, fields| fields.is_a?(Hash) }
                       .transform_values { |fields| fields.select { |_name, value| value.is_a?(String) } }
  end
end
