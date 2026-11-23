# frozen_string_literal: true

class Riffer::Rig::Stores::BaselineEntry
  extend Riffer::Rig::Support::TypedValue::Schema #[String]
  include Riffer::Rig::Support::TypedValue #[String]
  include Riffer::Rig::Stores::Stamped

  typed_value 'baseline', :system, :sections, :recorded_at

  # @dynamic system, sections, recorded_at
  attr_reader :system #: Array[String]
  attr_reader :sections #: Hash[Symbol, String]
  attr_reader :recorded_at #: String?

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: ::Riffer::Rig::Stores::BaselineEntry?
  def self.from_hash(hash)
    system = hash[:system]
    sections = hash[:sections]
    return nil unless system.is_a?(Array) && system.all?(String)
    return nil unless sections.is_a?(Hash) && sections.values.all?(String)

    new(system: system, sections: sections, recorded_at: Riffer::Rig::Stores::Timestamp.normalize(hash[:recorded_at]))
  end

  # @rbs system: Array[String]
  # @rbs sections: Hash[Symbol, String]
  # @rbs recorded_at: String?
  # @rbs return: void
  def initialize(system:, sections:, recorded_at: nil)
    @system = system
    @sections = sections
    @recorded_at = recorded_at
    freeze
  end
end
