# frozen_string_literal: true

module Riffer::Rig::Terminal::Markdown::Table
  extend self

  # Every row is padded to the grid's width, so without a ceiling one long
  # cell costs its length again on every other row.
  WIDTH_LIMIT = 500 #: Integer

  # Narrower than this a column breaks most words apart.
  MIN_COLUMN_WIDTH = 8 #: Integer

  DIVIDER = '─┼─' #: String

  LABEL_SEPARATOR = Riffer::Rig::Terminal::Markdown::Span.new(text: ': ') #: Riffer::Rig::Terminal::Markdown::Span

  # Columns can't measure a link's escapes, so a cell is padded by the width of
  # its unpainted twin.
  UNPAINTED = Riffer::Rig::Terminal::Theme.new(enabled: false) #: Riffer::Rig::Terminal::Theme

  # @rbs chunk: Array[String]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: Array[String]
  def lines(chunk, theme:, width:)
    grid = grid(chunk, theme)
    room = width && width < WIDTH_LIMIT ? width : WIDTH_LIMIT
    natural = grid.transpose.map { |column| column.map { |spans| cell_width(spans) }.max.to_i }
    widths = fit(natural, room)
    widths ? layout(grid, widths, theme) : records(grid, theme, room)
  end

  private

  # @rbs chunk: Array[String]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: Array[Array[Array[Riffer::Rig::Terminal::Markdown::Span]]]
  def grid(chunk, theme)
    header, _divider, *body = chunk.map { |line| cells(line) }
    rows = [header || [], *body]
    columns = rows.map(&:size).max.to_i
    rows.each_with_index.map do |row, index|
      styles = index.zero? ? [:bold] : [] #: Array[Symbol]
      (row + Array.new(columns - row.size, '')).map do |cell|
        Riffer::Rig::Terminal::Markdown::Inline.parse(cell, plain: !theme.enabled, styles: styles)
      end
    end
  end

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

  # @rbs natural: Array[Integer]
  # @rbs room: Integer
  # @rbs return: Array[Integer]?
  def fit(natural, room)
    return natural if breadth(natural) <= room

    cap = room.downto(MIN_COLUMN_WIDTH).find { |limit| breadth(capped(natural, limit)) <= room }
    cap && capped(natural, cap)
  end

  # @rbs widths: Array[Integer]
  # @rbs cap: Integer
  # @rbs return: Array[Integer]
  def capped(widths, cap)
    widths.map { |width| [width, cap].min }
  end

  # @rbs widths: Array[Integer]
  # @rbs return: Integer
  def breadth(widths)
    widths.sum + (DIVIDER.length * (widths.size - 1))
  end

  # @rbs grid: Array[Array[Array[Riffer::Rig::Terminal::Markdown::Span]]]
  # @rbs widths: Array[Integer]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: Array[String]
  def layout(grid, widths, theme)
    head, *rest = grid.map { |row| row(row, widths, theme) }
    [*head, theme.dim(widths.map { |width| '─' * width }.join(DIVIDER)), *rest.flatten]
  end

  # @rbs row: Array[Array[Riffer::Rig::Terminal::Markdown::Span]]
  # @rbs widths: Array[Integer]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: Array[String]
  def row(row, widths, theme)
    cells = row.zip(widths).map { |spans, width| cell(spans, width.to_i, theme) }
    height = cells.map(&:size).max.to_i
    filled = cells.zip(widths).map { |lines, width| lines + Array.new(height - lines.size, ' ' * width.to_i) }
    filled.transpose.map { |line| line.join(" #{theme.dim('│')} ").rstrip }
  end

  # @rbs spans: Array[Riffer::Rig::Terminal::Markdown::Span]
  # @rbs width: Integer
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: Array[String]
  def cell(spans, width, theme)
    # The Wrapper folds runs of spaces whenever it has a width, so a cell that
    # fits keeps its spacing only by not being wrapped at all.
    wrap = cell_width(spans) > width ? width : nil
    plain = Riffer::Rig::Terminal::Markdown::Flow.lines(spans, theme: UNPAINTED, width: wrap)
    painted = Riffer::Rig::Terminal::Markdown::Flow.lines(spans, theme: theme, width: wrap)
    painted.zip(plain).map { |line, text| "#{line}#{' ' * (width - Riffer::Rig::Terminal::Columns.width(text.to_s))}" }
  end

  # @rbs grid: Array[Array[Array[Riffer::Rig::Terminal::Markdown::Span]]]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer
  # @rbs return: Array[String]
  def records(grid, theme, width)
    header, *body = grid
    labels = header.to_a
    if body.empty?
      labels.flat_map { |label| Riffer::Rig::Terminal::Markdown::Flow.lines(label, theme: theme, width: width) }
    else
      body.flat_map { |row| ['', *record(labels, row, theme, width)] }.drop(1)
    end
  end

  # @rbs labels: Array[Array[Riffer::Rig::Terminal::Markdown::Span]]
  # @rbs row: Array[Array[Riffer::Rig::Terminal::Markdown::Span]]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer
  # @rbs return: Array[String]
  def record(labels, row, theme, width)
    labels.zip(row).flat_map do |label, value|
      Riffer::Rig::Terminal::Markdown::Flow.lines([*label, LABEL_SEPARATOR, *value.to_a], theme: theme, width: width)
    end
  end
end
