# frozen_string_literal: true

module Riffer::Rig::Terminal::Markdown::Table
  extend self

  # Every row is padded to the grid's width, so without a ceiling one long
  # cell costs its length again on every other row.
  WIDTH_LIMIT = 500 #: Integer

  # @rbs chunk: Array[String]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: Array[String]?
  def lines(chunk, theme:)
    header, _divider, *body = chunk.map { |line| cells(line) }
    rows = [header || [], *body]
    columns = rows.map(&:size).max.to_i
    grid = rows.each_with_index.map do |row, index|
      styles = index.zero? ? [:bold] : [] #: Array[Symbol]
      (row + Array.new(columns - row.size, '')).map do |cell|
        Riffer::Rig::Terminal::Markdown::Inline.parse(cell, plain: !theme.enabled, styles: styles)
      end
    end
    widths = grid.transpose.map { |column| column.map { |spans| cell_width(spans) }.max.to_i }
    rule = widths.map { |width| '─' * width }.join('─┼─')
    return nil if rule.length > WIDTH_LIMIT

    head, *rest = grid.map { |row| join(row, widths, theme) }
    [head.to_s, theme.dim(rule), *rest]
  end

  private

  # @rbs line: String
  # @rbs return: Array[String]
  def cells(line)
    line.strip.delete_prefix('|').delete_suffix('|').split(/(?<!\\)\|/, -1).map { |cell| cell.strip.gsub('\|', '|') }
  end

  # @rbs spans: Array[Riffer::Rig::Terminal::Markdown::Span]
  # @rbs return: Integer
  def cell_width(spans)
    Riffer::Rig::Terminal::Columns.width(spans.map(&:text).join)
  end

  # @rbs row: Array[Array[Riffer::Rig::Terminal::Markdown::Span]]
  # @rbs widths: Array[Integer]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: String
  def join(row, widths, theme)
    padded = row.zip(widths).map do |spans, width|
      painted = spans.empty? ? '' : Riffer::Rig::Terminal::Markdown::Flow.lines(spans, theme: theme, width: nil).join
      "#{painted}#{' ' * (width.to_i - cell_width(spans))}"
    end
    padded.join(" #{theme.dim('│')} ").rstrip
  end
end
