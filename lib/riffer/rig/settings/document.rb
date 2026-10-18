# frozen_string_literal: true

class Riffer::Rig::Settings::Document
  # @dynamic model, reasoning, catalog_files, providers, disabled, autoload, native_tools, save, reload
  attr_reader :model #: String?
  attr_reader :reasoning #: String?
  attr_reader :catalog_files #: Array[String]
  attr_reader :providers #: Hash[String, Hash[String, String]]
  attr_reader :disabled #: Array[String]
  attr_reader :autoload #: bool
  attr_reader :native_tools #: Hash[Symbol, bool | Hash[Symbol, untyped]]
  attr_reader :save #: bool
  attr_reader :reload #: (:auto | :manual)

  # @rbs source: Hash[Symbol, untyped]
  # @rbs return: void
  def initialize(source)
    @model = source[:model].is_a?(String) ? source[:model] : nil
    @reasoning = source[:reasoning].is_a?(String) ? source[:reasoning] : nil
    paths = source[:catalog_files]
    no_files = [] #: Array[String]
    @catalog_files = paths.is_a?(Array) && paths.all?(String) ? paths.dup.freeze : no_files.freeze
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
    @save = hash_or_empty(source[:sessions])[:save] != false
    @reload = source[:reload] == 'manual' ? :manual : :auto
    @native_tools = hash_or_empty(hash_or_empty(source[:tools])[:native])
                    .select { |_tool, switch| switch == true || switch.is_a?(Hash) }
                    .transform_keys(&:to_sym).freeze
    freeze
  end

  private

  # @rbs value: untyped
  # @rbs return: Hash[Symbol, untyped]
  def hash_or_empty(value)
    value.is_a?(Hash) ? value : {}
  end
end
