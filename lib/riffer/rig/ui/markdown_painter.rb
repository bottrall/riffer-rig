# frozen_string_literal: true

require_relative 'markdown'

class Riffer::Rig::UI::MarkdownPainter
  MIN_WIDTH = 20
  MAX_WIDTH = 500

  def initialize(io:, theme:, highlighter: Riffer::Rig::UI::Markdown::Highlighter.new(theme))
    @io = io
    @theme = theme
    @highlighter = highlighter
    @source = +''
    @row_count = 0
    @last_lines = nil
  end

  # On a TTY the smoother delivers paced slices, each triggering a repaint;
  # the reveal cadence (and with it the typing feel) stays in its pacing.
  # Off-TTY it delivers whole blocks, each rendered once as plain text.
  def <<(content)
    @source << content
    repaint if tty?
    self
  end

  # Rows painted here are final; ownership passes to the terminal scrollback.
  def finish
    repaint
    @source = +''
    @row_count = 0
    @last_lines = nil
  end

  private

  def repaint
    return if @source.empty?

    lines = Riffer::Rig::UI::Markdown::Walker.render(@source, width: width, theme: @theme, highlighter: @highlighter)
    return if lines == @last_lines

    if tty?
      erase_rows
      lines.each { |line| @io.print("\e[2K#{line}\r\n") }
    else
      lines.each { |line| @io.puts(line) }
      @source = +''
    end
    @io.flush
    @row_count = lines.length
    @last_lines = lines
  end

  def erase_rows
    return unless @row_count.positive?

    @io.print("\e[#{@row_count}A\e[J")
  end

  def width
    tty? ? @io.winsize[1].clamp(MIN_WIDTH, MAX_WIDTH) : MAX_WIDTH
  end

  def tty?
    @io.respond_to?(:tty?) && @io.tty?
  end
end
