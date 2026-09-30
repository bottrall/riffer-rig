# frozen_string_literal: true

class Riffer::Rig::Terminal::Theme
  # @rbs @enabled: bool

  # @dynamic enabled
  attr_reader :enabled #: bool

  # @rbs enabled: bool
  # @rbs return: void
  def initialize(enabled:)
    @enabled = enabled
  end

  # @rbs io: IO
  # @rbs no_color: bool
  # @rbs return: Riffer::Rig::Terminal::Theme
  def self.for(io, no_color: false)
    new(enabled: io.tty? && !no_color)
  end

  # @rbs text: String
  # @rbs rgb: Array[Integer]
  # @rbs return: String
  def paint(text, rgb)
    return text unless enabled

    "\e[38;2;#{rgb[0]};#{rgb[1]};#{rgb[2]}m#{text}\e[0m"
  end

  # @rbs text: String
  # @rbs return: String
  def pink(text) = paint(text, Riffer::Rig::Terminal::Palette::PINK)

  # @rbs text: String
  # @rbs return: String
  def magenta(text) = paint(text, Riffer::Rig::Terminal::Palette::MAGENTA)

  # @rbs text: String
  # @rbs return: String
  def purple(text) = paint(text, Riffer::Rig::Terminal::Palette::PURPLE)

  # @rbs text: String
  # @rbs return: String
  def blue(text) = paint(text, Riffer::Rig::Terminal::Palette::BLUE)

  # @rbs text: String
  # @rbs return: String
  def cyan(text) = paint(text, Riffer::Rig::Terminal::Palette::CYAN)

  # @rbs text: String
  # @rbs return: String
  def grey(text) = paint(text, Riffer::Rig::Terminal::Palette::GREY)

  # @rbs text: String
  # @rbs return: String
  def red(text) = paint(text, Riffer::Rig::Terminal::Palette::RED)

  # @rbs text: String
  # @rbs return: String
  def dim(text)
    return text unless enabled

    "\e[2m#{text}\e[0m"
  end

  # @rbs text: String
  # @rbs return: String
  def bold(text)
    return text unless enabled

    "\e[1m#{text}\e[0m"
  end
end
