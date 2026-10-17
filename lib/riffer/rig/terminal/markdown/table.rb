# frozen_string_literal: true

module Riffer::Rig::Terminal::Markdown::Table
  extend self

  # Rows are padded to the grid's width, so with no terminal width to wrap to
  # one long cell would pad every other row to its length.
  WIDTH_LIMIT = 500 #: Integer

  # GFM splits at a pipe inside a code span, but models rarely escape one
  # there, so a code span keeps its pipes. A tick run with no closer is matched
  # whole, so a later tick in it opens no span.
  CELL = /\|(?<cell>(?:#{Riffer::Rig::Terminal::Markdown::Inline::CODE}|\\.|`+|[^|])*)/ #: Regexp

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
    columns = grid.transpose
    natural = columns.map { |column| column.map { |spans| cell_width(spans) }.max.to_i }
    words = columns.map { |column| column.flat_map { |spans| word_widths(spans) }.max.to_i }
    widths = fit(natural, words, room)
    widths ? layout(grid, widths, theme) : records(grid, theme, room)
  end

  private

  # @rbs chunk: Array[String]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: Array[Array[Array[Riffer::Rig::Terminal::Markdown::Span]]]
  def grid(chunk, theme)
    header, _divider, *body = chunk.map { |line| cells(line) }
    columns = header.to_a.size
    [header.to_a, *body].each_with_index.map do |row, index|
      styles = index.zero? ? [:bold] : [] #: Array[Symbol]
      Array.new(columns) do |column|
        Riffer::Rig::Terminal::Markdown::Inline.parse(row.fetch(column, ''), plain: !theme.enabled, styles: styles)
      end
    end
  end

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

  # @rbs spans: Array[Riffer::Rig::Terminal::Markdown::Span]
  # @rbs return: Array[Integer]
  def word_widths(spans)
    spans.map(&:text).join.split.map { |word| Riffer::Rig::Terminal::Columns.width(word) }
  end

  # @rbs natural: Array[Integer]
  # @rbs words: Array[Integer]
  # @rbs room: Integer
  # @rbs return: Array[Integer]?
  def fit(natural, words, room)
    return natural if breadth(natural) <= room

    floors = clamped(natural, words, MIN_COLUMN_WIDTH)
    shrink(natural, words, room) || shrink(floors, Array.new(floors.size, 0), room)
  end

  # @rbs tops: Array[Integer]
  # @rbs bottoms: Array[Integer]
  # @rbs room: Integer
  # @rbs return: Array[Integer]?
  def shrink(tops, bottoms, room)
    cap = room.downto(MIN_COLUMN_WIDTH).find { |limit| breadth(clamped(tops, bottoms, limit)) <= room }
    cap && clamped(tops, bottoms, cap)
  end

  # @rbs tops: Array[Integer]
  # @rbs bottoms: Array[Integer]
  # @rbs cap: Integer
  # @rbs return: Array[Integer]
  def clamped(tops, bottoms, cap)
    tops.zip(bottoms).map { |top, bottom| cap.clamp(bottom.to_i, top) }
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
