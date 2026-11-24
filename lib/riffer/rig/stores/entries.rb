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
  # @rbs return: Riffer::Rig::Runtime::Snapshot
  def snapshot(entries, id)
    Riffer::Rig::Runtime::Snapshot.new(
      id: id,
      messages: replayed(entries),
      model: entries.filter_map { |entry| entry.model if entry.is_a?(Riffer::Rig::Stores::ModelEntry) }.last,
      reasoning: entries.filter_map do |entry|
        entry.reasoning if entry.is_a?(Riffer::Rig::Stores::ReasoningEntry)
      end.last,
      skills: entries.filter_map { |entry| entry.skill if entry.is_a?(Riffer::Rig::Stores::SkillEntry) }
    )
  end

  private

  # @rbs entries: Array[Riffer::Rig::Stores::entry]
  # @rbs return: Array[Riffer::Messages::Base]
  def replayed(entries)
    recorded = entries.grep(Riffer::Rig::Stores::MessageEntry) #: Array[Riffer::Rig::Stores::MessageEntry]
    # A session saved before rig recorded its head records one on resume, after
    # the messages produced under an earlier head: their reasoning, signed
    # under that head, is dropped, and the head moves back to the front.
    opened_at = recorded.index { |entry| entry.message[:role].to_s == 'system' }
    messages = recorded.each_with_index.map do |entry, index|
      signed = opened_at && index > opened_at
      Riffer::Rig::Runtime::Snapshot.message(signed ? entry.message : entry.message.except(:reasoning))
    end
    system, conversation = messages.partition { |message| message.is_a?(Riffer::Messages::System) }
    [*system, *conversation]
  end
end
