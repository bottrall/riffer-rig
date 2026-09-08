# frozen_string_literal: true

require_relative 'markdown'

class Riffer::Rig::UI::MarkdownPainter
  MIN_WIDTH = 20 #: Integer
  MAX_WIDTH = 500 #: Integer

  # @rbs @io: untyped
  # @rbs @theme: Riffer::Rig::UI::Theme
  # @rbs @highlighter: Riffer::Rig::UI::Markdown::Highlighter
  # @rbs @source: String
  # @rbs @row_count: Integer
  # @rbs @last_lines: Array[String]?

  # @rbs io: untyped
  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs highlighter: Riffer::Rig::UI::Markdown::Highlighter
  # @rbs return: void
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
  #
  # @rbs content: String
  # @rbs return: self
  def <<(content)
    @source << content
    repaint if tty?
    self
  end

  # Rows painted here are final; ownership passes to the terminal scrollback.
  #
  # @rbs return: void
  def finish
    repaint
    @source = +''
    @row_count = 0
    @last_lines = nil
  end

  private

  # @rbs return: void
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

  # @rbs return: void
  def erase_rows
    return unless @row_count.positive?

    @io.print("\e[#{@row_count}A\e[J")
  end

  # @rbs return: Integer
  def width
    return MAX_WIDTH unless tty?

    @io.winsize[1].clamp(MIN_WIDTH, MAX_WIDTH) # : Integer
  end

  # @rbs return: bool
  def tty?
    @io.respond_to?(:tty?) && @io.tty?
  end
end
