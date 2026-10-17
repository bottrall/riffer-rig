# frozen_string_literal: true

module Riffer::Rig::Terminal::Markdown::Table
  extend self

  # Every row is padded to the grid's width, so without a ceiling one long
  # cell costs its length again on every other row.
  WIDTH_LIMIT = 500 #: Integer

  # GFM splits at a pipe inside a code span, but models rarely escape one
  # there, so a code span keeps its pipes. A tick run with no closer is matched
  # whole, so a later tick in it opens no span.
  CELL = /\|(?<cell>(?:#{Riffer::Rig::Terminal::Markdown::Inline::CODE}|\\.|`+|[^|])*)/ #: Regexp

  # @rbs chunk: Array[String]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: Array[String]?
  def lines(chunk, theme:)
    header, _divider, *body = chunk.map { |line| cells(line) }
    columns = header.to_a.size
    grid = [header.to_a, *body].each_with_index.map do |row, index|
      styles = index.zero? ? [:bold] : [] #: Array[Symbol]
      Array.new(columns) do |column|
        Riffer::Rig::Terminal::Markdown::Inline.parse(row.fetch(column, ''), plain: !theme.enabled, styles: styles)
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
    row = "|#{line.strip.delete_prefix('|').delete_suffix('|')}"
    row.enum_for(:scan, CELL).map { Regexp.last_match(:cell).to_s.strip.gsub('\|', '|') }
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
