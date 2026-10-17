# frozen_string_literal: true

module Riffer::Rig::Terminal::Question
  extend self

  INDENT = 2 #: Integer

  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs width: Integer?
  # @rbs return: Array[String]
  def lines(theme, question, options, width)
    numbered = (options || []).each.with_index(1).flat_map do |option, number|
      lead = "#{' ' * INDENT}#{theme.magenta("#{number}.")} "
      hang(lead, option, Riffer::Rig::Terminal::Columns.width(lead), width)
    end
    [question].compact.flat_map { |text| hang('', text, INDENT, width) } + numbered
  end

  private

  # @rbs lead: String
  # @rbs text: String
  # @rbs indent: Integer
  # @rbs width: Integer?
  # @rbs return: Array[String]
  def hang(lead, text, indent, width)
    line = "#{lead}#{text}"
    # Wrapping packs words with single spaces, so a line that fits keeps its
    # own spacing.
    return [line] if width.nil? || Riffer::Rig::Terminal::Columns.width(line) <= width

    wrapped = Riffer::Rig::Terminal::Wrapper.new(width: width, indent: indent) << "#{text}\n"
    "#{lead}#{wrapped.delete_prefix(' ' * indent)}".lines(chomp: true)
  end
end
