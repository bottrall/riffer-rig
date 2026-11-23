# frozen_string_literal: true

class Riffer::Rig::Runtime::Baseline
  include Riffer::Rig::Support::Equatable

  # @dynamic system, sections
  attr_reader :system #: Array[String]
  attr_reader :sections #: Hash[Symbol, String]

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: Riffer::Rig::Runtime::Baseline
  def self.from_h(hash)
    new(system: hash.fetch(:system), sections: hash.fetch(:sections))
  end

  # @rbs system: Array[String]
  # @rbs sections: Hash[Symbol, String]
  # @rbs return: void
  def initialize(system:, sections:)
    @system = system
    @sections = sections
    freeze
  end

  # @rbs messages: Array[Riffer::Messages::Base]
  # @rbs return: Array[Riffer::Messages::Base]
  def head(messages)
    [
      *@system.map { |text| Riffer::Messages::System.new(text) },
      *messages.drop_while { |message| message.is_a?(Riffer::Messages::System) }
    ]
  end

  # @rbs messages: Array[Riffer::Messages::Base]
  # @rbs current: Hash[Symbol, String]
  # @rbs return: Hash[Symbol, String?]
  def changes(messages, current)
    updates = messages.grep(Riffer::Rig::Runtime::ContextUpdate) #: Array[Riffer::Rig::Runtime::ContextUpdate]
    seen = updates.reduce(@sections) { |folded, update| folded.merge(update.sections).compact }
    (seen.keys | current.keys).reject { |name| seen[name] == current[name] }.to_h { |name| [name, current[name]] }
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { system: @system, sections: @sections }
  end
end
