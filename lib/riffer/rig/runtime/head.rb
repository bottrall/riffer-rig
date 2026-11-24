# frozen_string_literal: true

module Riffer::Rig::Runtime::Head
  extend self

  # @rbs messages: Array[Riffer::Messages::Base]
  # @rbs return: Hash[Symbol, String]?
  def sections(messages)
    head = messages.first
    return unless head.is_a?(Riffer::Messages::System)

    sections = Riffer::Rig::Runtime::SystemPrompt.sections(head.content)
    # Rig renders the environment into every head it opens; a system message
    # without one is riffer's skills catalog or an older version's prompt.
    sections if sections.key?(Riffer::Rig::Runtime::SystemPrompt::ENVIRONMENT)
  end

  # @rbs messages: Array[Riffer::Messages::Base]
  # @rbs return: Hash[Symbol, String]?
  def seen(messages)
    opened = sections(messages)
    return unless opened

    updates = messages.grep(Riffer::Rig::Runtime::ContextUpdate) #: Array[Riffer::Rig::Runtime::ContextUpdate]
    updates.reduce(opened) { |folded, update| folded.merge(update.sections).compact }
  end

  # @rbs seen: Hash[Symbol, String]
  # @rbs current: Hash[Symbol, String]
  # @rbs return: Hash[Symbol, String?]
  def changes(seen, current)
    (seen.keys | current.keys).reject { |name| seen[name] == current[name] }.to_h { |name| [name, current[name]] }
  end
end
