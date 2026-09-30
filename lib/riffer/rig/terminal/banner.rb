# frozen_string_literal: true

module Riffer::Rig::Terminal::Banner
  extend self

  WORDMARK = [
    '██████╗ ██╗███████╗███████╗███████╗██████╗ ',
    '██╔══██╗██║██╔════╝██╔════╝██╔════╝██╔══██╗',
    '██████╔╝██║█████╗  █████╗  █████╗  ██████╔╝',
    '██╔══██╗██║██╔══╝  ██╔══╝  ██╔══╝  ██╔══██╗',
    '██║  ██║██║██║     ██║     ███████╗██║  ██║',
    '╚═╝  ╚═╝╚═╝╚═╝     ╚═╝     ╚══════╝╚═╝  ╚═╝'
  ].freeze #: Array[String]

  ROW_COLOURS = [
    Riffer::Rig::Terminal::Palette::PINK,
    Riffer::Rig::Terminal::Palette::MAGENTA,
    Riffer::Rig::Terminal::Palette::PURPLE,
    Riffer::Rig::Terminal::Palette::BLUE,
    Riffer::Rig::Terminal::Palette::CYAN,
    Riffer::Rig::Terminal::Palette::CYAN
  ].freeze #: Array[Array[Integer]]

  INFO_LABEL_WIDTH = 8 #: Integer

  INDENT = '  ' #: String

  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs model: String
  # @rbs cwd: String
  # @rbs skills: String
  # @rbs version: String
  # @rbs return: String
  def call(theme, model:, cwd:, skills:, version:)
    lines(theme, model: model, cwd: cwd, skills: skills, version: version).join("\n")
  end

  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs model: String
  # @rbs cwd: String
  # @rbs skills: String
  # @rbs version: String
  # @rbs return: Array[String]
  def lines(theme, model:, cwd:, skills:, version:)
    [''] + art(theme) + [''] + info(theme, model: model, cwd: cwd, skills: skills, version: version) + ['']
  end

  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: Array[String]
  def art(theme)
    art = WORDMARK.each_index.map { |i| "#{INDENT}#{theme.paint(WORDMARK[i], ROW_COLOURS[i])}" }
    art + ["#{INDENT}#{theme.cyan("♪ let's riff ♪")}"]
  end

  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs model: String
  # @rbs cwd: String
  # @rbs skills: String
  # @rbs version: String
  # @rbs return: Array[String]
  def info(theme, model:, cwd:, skills:, version:)
    rows = { model: model, cwd: cwd, skills: skills, version: version }.map do |label, value|
      "  #{theme.magenta('▸')} #{theme.grey(label.to_s.ljust(INFO_LABEL_WIDTH))}#{value}"
    end
    rows + ['', "  #{theme.dim('type /exit to quit')}"]
  end
end
