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
    baseline_at = entries.rindex { |entry| entry.is_a?(Riffer::Rig::Stores::BaselineEntry) }
    baseline = baseline_at && entries[baseline_at] #: Riffer::Rig::Stores::BaselineEntry?
    Riffer::Rig::Runtime::Snapshot.new(
      id: id,
      messages: replayed(entries, baseline_at),
      model: entries.filter_map { |entry| entry.model if entry.is_a?(Riffer::Rig::Stores::ModelEntry) }.last,
      reasoning: entries.filter_map do |entry|
        entry.reasoning if entry.is_a?(Riffer::Rig::Stores::ReasoningEntry)
      end.last,
      skills: entries.filter_map { |entry| entry.skill if entry.is_a?(Riffer::Rig::Stores::SkillEntry) },
      baseline: baseline && Riffer::Rig::Runtime::Baseline.new(system: baseline.system, sections: baseline.sections)
    )
  end

  private

  # @rbs entries: Array[Riffer::Rig::Stores::entry]
  # @rbs baseline_at: Integer?
  # @rbs return: Array[Riffer::Messages::Base]
  def replayed(entries, baseline_at)
    entries.each_with_index.filter_map do |entry, index|
      next unless entry.is_a?(Riffer::Rig::Stores::MessageEntry)

      # Reasoning is signed under the system message it was produced with, and
      # only the messages after the last baseline entry were produced under it.
      signed = baseline_at && index > baseline_at
      Riffer::Rig::Runtime::Snapshot.message(signed ? entry.message : entry.message.except(:reasoning))
    end
  end
end
