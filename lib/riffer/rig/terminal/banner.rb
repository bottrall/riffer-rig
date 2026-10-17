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

  ART_COLUMNS = INDENT.size + Riffer::Rig::Terminal::Columns.width(WORDMARK[0]) #: Integer

  MARKER = '▸' #: String

  VALUE_COLUMN = Riffer::Rig::Terminal::Columns.width("#{INDENT}#{MARKER} ") + INFO_LABEL_WIDTH #: Integer

  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs model: String
  # @rbs cwd: String
  # @rbs skills: String
  # @rbs version: String
  # @rbs tally: Riffer::Providers::TokenUsage?
  # @rbs width: Integer?
  # @rbs return: String
  def call(theme, model:, cwd:, skills:, version:, tally: nil, width: nil)
    lines(theme, model: model, cwd: cwd, skills: skills, version: version, tally: tally, width: width).join("\n")
  end

  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs model: String
  # @rbs cwd: String
  # @rbs skills: String
  # @rbs version: String
  # @rbs tally: Riffer::Providers::TokenUsage?
  # @rbs width: Integer?
  # @rbs return: Array[String]
  def lines(theme, model:, cwd:, skills:, version:, tally:, width:)
    rows = info(theme, model: model, cwd: cwd, skills: skills, version: version, tally: tally, width: width)
    [''] + art(theme, width) + [''] + rows + ['']
  end

  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: Array[String]
  def art(theme, width)
    tagline = "#{INDENT}#{theme.cyan("♪ let's riff ♪")}"
    return [tagline] if width && width < ART_COLUMNS

    WORDMARK.each_index.map { |i| "#{INDENT}#{theme.paint(WORDMARK[i], ROW_COLOURS[i])}" } + [tagline]
  end

  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs model: String
  # @rbs cwd: String
  # @rbs skills: String
  # @rbs version: String
  # @rbs tally: Riffer::Providers::TokenUsage?
  # @rbs width: Integer?
  # @rbs return: Array[String]
  def info(theme, model:, cwd:, skills:, version:, tally:, width:)
    room = width && (width - VALUE_COLUMN)
    session = tally && Riffer::Rig::Terminal::Tally.call(tally)
    values = {
      model: clip(model, room),
      cwd: clip(cwd, room),
      skills: skills,
      version: version,
      session: session
    }.compact
    rows = values.map do |label, value|
      "#{INDENT}#{theme.magenta(MARKER)} #{theme.grey(label.to_s.ljust(INFO_LABEL_WIDTH))}#{value}"
    end
    rows + ['', "  #{theme.dim('type /exit to quit')}"]
  end

  private

  # The end of a path or model id is what tells it apart, so the cut takes the front.
  # @rbs value: String
  # @rbs room: Integer?
  # @rbs return: String
  def clip(value, room)
    return value if room.nil? || Riffer::Rig::Terminal::Columns.width(value) <= room

    "…#{Riffer::Rig::Terminal::Columns.tail(value, room - 1)}"
  end
end
