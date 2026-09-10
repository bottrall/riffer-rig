# frozen_string_literal: true

module Riffer::Rig::UI::Banner
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
    Riffer::Rig::UI::Palette::PINK,
    Riffer::Rig::UI::Palette::MAGENTA,
    Riffer::Rig::UI::Palette::PURPLE,
    Riffer::Rig::UI::Palette::BLUE,
    Riffer::Rig::UI::Palette::CYAN,
    Riffer::Rig::UI::Palette::CYAN
  ].freeze #: Array[Array[Integer]]

  INFO_LABEL_WIDTH = 8 #: Integer

  INDENT = '  ' #: String

  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs model: String
  # @rbs cwd: String
  # @rbs context: String
  # @rbs skills: String
  # @rbs version: String
  # @rbs return: String
  def call(theme, model:, cwd:, context:, skills:, version:)
    lines(theme, model: model, cwd: cwd, context: context, skills: skills, version: version).join("\n")
  end

  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs model: String
  # @rbs cwd: String
  # @rbs context: String
  # @rbs skills: String
  # @rbs version: String
  # @rbs return: Array[String]
  def lines(theme, model:, cwd:, context:, skills:, version:)
    [''] + art(theme) + [''] +
      info(theme, model: model, cwd: cwd, context: context, skills: skills, version: version) + ['']
  end

  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs return: Array[String]
  def art(theme)
    art = WORDMARK.each_index.map { |i| "#{INDENT}#{theme.paint(WORDMARK[i], ROW_COLOURS[i])}" }
    art + ["#{INDENT}#{theme.cyan("♪ let's riff ♪")}"]
  end

  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs model: String
  # @rbs cwd: String
  # @rbs context: String
  # @rbs skills: String
  # @rbs version: String
  # @rbs return: Array[String]
  def info(theme, model:, cwd:, context:, skills:, version:)
    rows = { model: model, cwd: cwd, context: context, skills: skills, version: version }.map do |label, value|
      "  #{theme.magenta('▸')} #{theme.grey(label.to_s.ljust(INFO_LABEL_WIDTH))}#{value}"
    end
    rows + ['', "  #{theme.dim('type /exit to quit')}"]
  end
end
