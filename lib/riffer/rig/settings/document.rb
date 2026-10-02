# frozen_string_literal: true

class Riffer::Rig::Settings::Document
  # @dynamic model, reasoning, models, providers, disabled, autoload
  attr_reader :model #: String?
  attr_reader :reasoning #: String?
  attr_reader :models #: Hash[String, Riffer::Rig::Settings::Pricing]
  attr_reader :providers #: Hash[String, Hash[String, String]]
  attr_reader :disabled #: Array[String]
  attr_reader :autoload #: bool

  # @rbs source: Hash[Symbol, untyped]
  # @rbs return: void
  def initialize(source)
    @model = source[:model].is_a?(String) ? source[:model] : nil
    @reasoning = source[:reasoning].is_a?(String) ? source[:reasoning] : nil
    @models = hash_or_empty(source[:models]).filter_map do |name, entry|
      [name.to_s, Riffer::Rig::Settings::Pricing.from(entry)] if entry.is_a?(Hash)
    end.to_h.freeze
    @providers = hash_or_empty(source[:providers]).filter_map do |identifier, fields|
      if fields.is_a?(Hash)
        [identifier.to_s, fields.select do |_name, value|
          value.is_a?(String)
        end.transform_keys(&:to_s)]
      end
    end.to_h.freeze
    disabled = hash_or_empty(source[:extensions])[:disabled]
    names = disabled.is_a?(Array) ? disabled.grep(String) : [] #: Array[String]
    @disabled = names.freeze
    @autoload = hash_or_empty(source[:extensions])[:autoload] == true
    freeze
  end

  private

  # @rbs value: untyped
  # @rbs return: Hash[Symbol, untyped]
  def hash_or_empty(value)
    value.is_a?(Hash) ? value : {}
  end
end
