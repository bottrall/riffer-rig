# frozen_string_literal: true

module Riffer::Rig::Terminal::Question
  extend self

  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs return: Array[String]
  def lines(theme, question, options)
    numbered = (options || []).map.with_index(1) { |option, number| "  #{theme.magenta("#{number}.")} #{option}" }
    [question, *numbered].compact
  end
end
