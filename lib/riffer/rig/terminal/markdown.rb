# frozen_string_literal: true

module Riffer::Rig::Terminal::Markdown
  extend self

  # Tabs and newlines are the only control characters that survive: the source
  # is model output, and anything else here could drive the terminal.
  CONTROL = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f]/ #: Regexp

  TAB = '    ' #: String

  RULE_WIDTH = 40 #: Integer

  BULLET = '•' #: String

  FLUSH_ITEM = /\A(?<marker>#{Blocks::MARKER})(?: +|\z)/ #: Regexp

  # Quotes and lists render by recursion, so without a ceiling a single line of
  # quote marks could exhaust the stack.
  NESTING_LIMIT = 16 #: Integer

  # Every row is padded to the widest, so without a ceiling one wide row costs
  # a cell per column on every other row. A row's pipes bound its cells.
  COLUMN_LIMIT = 32 #: Integer

  # @rbs source: String
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String
  def render(source, theme:, width:)
    text = source.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    source_lines = text.gsub(/\r\n?/, "\n").gsub(CONTROL, '').gsub("\t", TAB).lines(chomp: true)
    rows = lines(source_lines, theme: theme, width: narrow(width, 0), depth: 0)
    body = rows.join("\n").gsub(/\A\n+|\n+\z/, '')
    body.empty? ? body : "#{body}\n"
  end

  private

  # @rbs source_lines: Array[String]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs depth: Integer
  # @rbs return: Array[String]
  def lines(source_lines, theme:, width:, depth:)
    return flow(source_lines.join(' '), theme: theme, width: width) if depth > NESTING_LIMIT

    Blocks.split(source_lines).flat_map { |chunk| block(chunk, theme: theme, width: width, depth: depth) }
  end

  # @rbs chunk: Array[String]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs depth: Integer
  # @rbs return: Array[String]
  def block(chunk, theme:, width:, depth:)
    case Blocks.kind(chunk, 0)
    when :blank then ['']
    when :fence then fence(chunk, theme: theme, width: width)
    when :heading then heading(chunk.fetch(0), theme: theme, width: width)
    when :rule then [theme.dim('─' * (width || RULE_WIDTH))]
    when :quote then quote(chunk, theme: theme, width: width, depth: depth)
    when :list then list(chunk, theme: theme, width: width, depth: depth)
    when :table then table(chunk, theme: theme, width: width)
    else flow(chunk.join(' '), theme: theme, width: width)
    end
  end

  # @rbs text: String
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs styles: Array[Symbol]
  # @rbs return: Array[String]
  def flow(text, theme:, width:, styles: [])
    # The Wrapper only folds spaces when it has a width to wrap to.
    spans = Inline.parse(text.squeeze(' ').strip, plain: !theme.enabled, styles: styles)
    Flow.lines(spans, theme: theme, width: width)
  end

  # @rbs line: String
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: Array[String]
  def heading(line, theme:, width:)
    title = line[Blocks::HEADING, :title].to_s
    # Without colour the marks are all that tells a heading from a paragraph.
    text = theme.enabled ? title : "#{line[Blocks::HEADING, :marks]} #{title}"
    flow(text, theme: theme, width: width, styles: [:heading])
  end

  # @rbs chunk: Array[String]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: Array[String]
  def fence(chunk, theme:, width:)
    opening = chunk.fetch(0)
    language = opening[Blocks::FENCE, :language].to_s
    indent = opening[Blocks::FENCE, :indent].to_s.length
    closed = chunk.size > 1 && Blocks.closing(opening[Blocks::FENCE, :fence].to_s).match?(chunk.fetch(-1))
    code = (closed ? chunk[1...-1] : chunk.drop(1)) || []
    limit = narrow(width, 2)
    # The Wrapper folds runs of spaces, which would destroy code's indentation,
    # so a long code line is cut at the width instead of wrapped through it.
    pieces = dedent(code, indent).flat_map do |row|
      limit && row.length > limit ? row.chars.each_slice(limit).map(&:join) : [row]
    end
    label = [language].reject(&:empty?).map { |name| theme.dim(name) }
    label + gutter(pieces.map { |piece| piece.empty? ? piece : theme.code(piece) }, "#{theme.dim('│')} ")
  end

  # @rbs chunk: Array[String]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs depth: Integer
  # @rbs return: Array[String]
  def quote(chunk, theme:, width:, depth:)
    quoted = chunk.map { |line| line.sub(Blocks::QUOTE, '') }
    gutter(lines(quoted, theme: theme, width: narrow(width, 2), depth: depth + 1), "#{theme.purple('┃')} ")
  end

  # @rbs chunk: Array[String]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs depth: Integer
  # @rbs return: Array[String]
  def list(chunk, theme:, width:, depth:)
    indent = chunk.fetch(0)[/\A */].to_s.length
    items = dedent(chunk, indent).slice_before(FLUSH_ITEM).to_a
    pad = items.map { |item| marker(item.fetch(0)).length }.max.to_i
    items.flat_map { |item| item(item, pad, theme: theme, width: width, depth: depth) }
  end

  # @rbs line: String
  # @rbs return: String
  def marker(line)
    source = line[FLUSH_ITEM, :marker].to_s
    source.match?(/\d/) ? source : BULLET
  end

  # @rbs source_lines: Array[String]
  # @rbs pad: Integer
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs depth: Integer
  # @rbs return: Array[String]
  def item(source_lines, pad, theme:, width:, depth:)
    first = source_lines.fetch(0)
    offset = first[FLUSH_ITEM].to_s.length
    content = [first[offset..].to_s, *dedent(source_lines.drop(1), offset)]
    body = lines(content, theme: theme, width: narrow(width, pad + 1), depth: depth + 1)
    lead = "#{theme.magenta(marker(first).rjust(pad))} "
    gutter(body.empty? ? [''] : body, lead, ' ' * (pad + 1))
  end

  # @rbs chunk: Array[String]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: Array[String]
  def table(chunk, theme:, width:)
    grid = Table.lines(chunk, theme: theme) unless chunk.any? { |line| line.count('|') > COLUMN_LIMIT }
    grid || flow(chunk.join(' '), theme: theme, width: width)
  end

  # @rbs source_lines: Array[String]
  # @rbs by: Integer
  # @rbs return: Array[String]
  def dedent(source_lines, by)
    source_lines.map { |line| line.sub(/\A */) { |spaces| spaces[by..].to_s } }
  end

  # @rbs rows: Array[String]
  # @rbs lead: String
  # @rbs rest: String
  # @rbs return: Array[String]
  def gutter(rows, lead, rest = lead)
    rows.each_with_index.map { |row, index| "#{index.zero? ? lead : rest}#{row}".rstrip }
  end

  # @rbs width: Integer?
  # @rbs by: Integer
  # @rbs return: Integer?
  def narrow(width, by)
    width && [width - by, 1].max
  end
end
