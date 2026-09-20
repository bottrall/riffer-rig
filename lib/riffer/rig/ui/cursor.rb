# frozen_string_literal: true

# A hidden cursor can't flicker against the animator's erase-and-redraw churn.
class Riffer::Rig::UI::Cursor
  HIDE = "\e[?25l" #: String

  SHOW = "\e[?25h" #: String

  # @rbs @io: IO
  # @rbs @theme: Riffer::Rig::UI::Theme

  # @rbs io: IO
  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs return: void
  def initialize(io: $stdout, theme: Riffer::Rig::UI::Theme.for(io))
    @io = io
    @theme = theme
  end

  # @rbs return: void
  def hide
    write(HIDE)
  end

  # @rbs return: void
  def show
    write(SHOW)
  end

  private

  # @rbs sequence: String
  # @rbs return: void
  def write(sequence)
    return unless enabled?

    @io.print(sequence)
    @io.flush
  end

  # @rbs return: bool
  def enabled?
    @theme.enabled && @io.tty?
  end
end
