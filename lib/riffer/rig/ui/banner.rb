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
  ].freeze

  ROW_COLOURS = [
    Riffer::Rig::UI::Palette::PINK,
    Riffer::Rig::UI::Palette::MAGENTA,
    Riffer::Rig::UI::Palette::PURPLE,
    Riffer::Rig::UI::Palette::BLUE,
    Riffer::Rig::UI::Palette::CYAN,
    Riffer::Rig::UI::Palette::CYAN
  ].freeze

  INFO_LABEL_WIDTH = 8
  INDENT = '  '

  def call(theme, model:, cwd:, context:, skills:, version:)
    lines(theme, model: model, cwd: cwd, context: context, skills: skills, version: version).join("\n")
  end

  def lines(theme, model:, cwd:, context:, skills:, version:)
    [''] + art(theme) + [''] +
      info(theme, model: model, cwd: cwd, context: context, skills: skills, version: version) + ['']
  end

  def art(theme)
    art = WORDMARK.each_index.map { |i| "#{INDENT}#{theme.paint(WORDMARK[i], ROW_COLOURS[i])}" }
    art + ["#{INDENT}#{theme.cyan("♪ let's riff ♪")}"]
  end

  def info(theme, model:, cwd:, context:, skills:, version:)
    rows = { model: model, cwd: cwd, context: context, skills: skills, version: version }.map do |label, value|
      "  #{theme.magenta('▸')} #{theme.grey(label.to_s.ljust(INFO_LABEL_WIDTH))}#{value}"
    end
    rows + ['', "  #{theme.dim('type /exit to quit')}"]
  end
end
