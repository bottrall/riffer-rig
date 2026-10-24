# frozen_string_literal: true

class Riffer::Rig::Terminal::Picker::Listing
  # @dynamic rows, filter
  attr_reader :rows #: Array[Riffer::Rig::Terminal::Session]
  attr_reader :filter #: String

  # @rbs rows: Array[Riffer::Rig::Terminal::Session]
  # @rbs filter: String
  # @rbs return: void
  def initialize(rows:, filter: '')
    @rows = rows.freeze
    @filter = filter
    freeze
  end

  # @rbs return: Array[Riffer::Rig::Terminal::Session]
  def shown
    rows.filter { |row| matches?(row, filter) }
  end

  # @rbs filter: String
  # @rbs return: bool
  def any_match?(filter)
    rows.any? { |row| matches?(row, filter) }
  end

  # @rbs filter: String
  # @rbs return: Riffer::Rig::Terminal::Picker::Listing
  def narrow(filter)
    self.class.new(rows: rows, filter: filter)
  end

  # @rbs rows: Array[Riffer::Rig::Terminal::Session]
  # @rbs return: Riffer::Rig::Terminal::Picker::Listing
  def relist(rows)
    relisted = self.class.new(rows: rows)
    relisted.any_match?(filter) ? relisted.narrow(filter) : relisted
  end

  private

  # @rbs row: Riffer::Rig::Terminal::Session
  # @rbs filter: String
  # @rbs return: bool
  def matches?(row, filter)
    filter.empty? || row.title.downcase.include?(filter.downcase)
  end
end
