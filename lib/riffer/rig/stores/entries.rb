# frozen_string_literal: true

module Riffer::Rig::Stores::Entries
  extend self

  # @rbs entries: Array[Riffer::Rig::Stores::entry]
  # @rbs return: Array[Hash[Symbol, untyped]]
  def messages(entries)
    entries.filter_map { |entry| entry.message if entry.is_a?(Riffer::Rig::Stores::MessageEntry) }
  end

  # @rbs entries: Array[Riffer::Rig::Stores::entry]
  # @rbs id: String
  # @rbs return: Hash[Symbol, untyped]
  def snapshot(entries, id)
    {
      id: id,
      messages: messages(entries),
      model: entries.filter_map { |entry| entry.model if entry.is_a?(Riffer::Rig::Stores::ModelEntry) }.last,
      skills: entries.filter_map { |entry| entry.skill if entry.is_a?(Riffer::Rig::Stores::SkillEntry) }
    }
  end
end
