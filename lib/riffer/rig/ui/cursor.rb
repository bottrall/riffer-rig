# frozen_string_literal: true

# Hides the terminal cursor while a turn is in flight: a hidden cursor can't
# flicker against the animator's erase-and-redraw churn.
class Riffer::Rig::UI::Cursor
  HIDE = "\e[?25l"
  SHOW = "\e[?25h"

  def initialize(io: $stdout, theme: Riffer::Rig::UI::Theme.for(io))
    @io = io
    @theme = theme
  end

  def hide
    write(HIDE)
  end

  def show
    write(SHOW)
  end

  private

  def write(sequence)
    return unless enabled?

    @io.print(sequence)
    @io.flush
  end

  def enabled?
    @theme.enabled && @io.respond_to?(:tty?) && @io.tty?
  end
end
