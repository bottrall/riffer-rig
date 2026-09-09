# frozen_string_literal: true

# +enabled+ gates every escape so the same code path emits plain, escape-free
# text when piped or tested.
class Riffer::Rig::UI::Theme
  # @rbs @enabled: bool

  # @rbs return: bool
  attr_reader :enabled #: bool

  # @rbs enabled: bool
  # @rbs return: void
  def initialize(enabled:)
    @enabled = enabled
  end

  # @rbs io: untyped
  # @rbs return: Riffer::Rig::UI::Theme
  def self.for(io)
    new(enabled: io.respond_to?(:tty?) && io.tty? && !ENV.key?('NO_COLOR'))
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
  def pink(text) = paint(text, Riffer::Rig::UI::Palette::PINK)

  # @rbs text: String
  # @rbs return: String
  def magenta(text) = paint(text, Riffer::Rig::UI::Palette::MAGENTA)

  # @rbs text: String
  # @rbs return: String
  def purple(text) = paint(text, Riffer::Rig::UI::Palette::PURPLE)

  # @rbs text: String
  # @rbs return: String
  def blue(text) = paint(text, Riffer::Rig::UI::Palette::BLUE)

  # @rbs text: String
  # @rbs return: String
  def cyan(text) = paint(text, Riffer::Rig::UI::Palette::CYAN)

  # @rbs text: String
  # @rbs return: String
  def grey(text) = paint(text, Riffer::Rig::UI::Palette::GREY)

  # @rbs text: String
  # @rbs return: String
  def red(text) = paint(text, Riffer::Rig::UI::Palette::RED)

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
