# frozen_string_literal: true

class Riffer::Rig::Runtime::ContextUpdate < Riffer::Messages::User
  MARKER = :context_update #: Symbol

  PREAMBLE = 'Your context changed since you last saw it. Each section below replaces its earlier version ' \
             'in full; a section marked removed no longer applies.'

  # @dynamic sections
  attr_reader :sections #: Hash[Symbol, String?]

  # @rbs changes: Hash[Symbol, String?]
  # @rbs return: Riffer::Rig::Runtime::ContextUpdate
  def self.of(changes)
    blocks = changes.map do |name, text|
      text ? Riffer::Rig::Runtime::SystemPrompt.section(name, text) : %(<section name="#{name}" removed="true"/>)
    end
    new(["<context-update>\n#{PREAMBLE}", *blocks, '</context-update>'].join("\n\n"), sections: changes)
  end

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: Riffer::Rig::Runtime::ContextUpdate
  def self.from_hash(hash)
    new(hash[:content], id: hash[:id], sections: hash.fetch(:sections))
  end

  # @rbs content: String
  # @rbs id: String?
  # @rbs files: Array[Riffer::Messages::User::FilePart]
  # @rbs sections: Hash[Symbol, String?]
  # @rbs return: void
  def initialize(content, id: nil, files: [], sections: {})
    # riffer's User#+ rebuilds a message of the same class with its files.
    super(content, id: id, files: files)
    @sections = sections
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    super.merge(MARKER => true, sections: sections)
  end
end
