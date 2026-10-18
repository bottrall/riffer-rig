# frozen_string_literal: true

class Riffer::Rig::Terminal::Wrapper
  # @rbs @width: Integer?
  # @rbs @indent: Integer
  # @rbs @verbatim: bool
  # @rbs @line: String

  # @rbs width: Integer?
  # @rbs indent: Integer
  # @rbs verbatim: bool
  # @rbs return: void
  def initialize(width:, indent:, verbatim: false)
    @width = width
    @indent = indent
    @verbatim = verbatim
    @line = ''
  end

  # @rbs text: String
  # @rbs return: String
  def <<(text)
    *terminated, last = "#{@line}#{text}".split(/\r?\n/, -1)
    pending = last.to_s
    *overflow, tail = wrap(pending)
    # A cut leaves the pending line starting on a word, so the whitespace at a
    # wrap boundary is never mistaken for the indentation of a new line.
    # Verbatim wrap is lossless, so tail already carries that whitespace there.
    remainder = @verbatim ? tail.to_s : "#{tail}#{pending[/\s*\z/]}"
    @line = overflow.empty? ? pending : remainder
    [*terminated.map { |line| blank?(line) ? "\n" : indented(wrap(line)) }, indented(overflow)].join
  end

  # @rbs return: String
  def flush
    pending = @line
    @line = ''
    blank?(pending) ? '' : indented(wrap(pending))
  end

  private

  # @rbs text: String
  # @rbs return: bool
  def blank?(text)
    @verbatim ? text.empty? : text.strip.empty?
  end

  # @rbs text: String
  # @rbs return: Array[String]
  def wrap(text)
    limit = usable_width
    return [text] unless limit

    units = @verbatim ? text.split(/(\s+)/) : words(text, limit)
    pieces = units.flat_map do |unit|
      Riffer::Rig::Terminal::Columns.width(unit) > limit ? pack(unit.grapheme_clusters, limit, '') : [unit]
    end
    pack(pieces, limit, @verbatim ? '' : ' ')
  end

  # @rbs text: String
  # @rbs limit: Integer
  # @rbs return: Array[String]
  def words(text, limit)
    first, *rest = text.split
    return [] unless first

    led = "#{text[/\A\s*/]}#{first}"
    [Riffer::Rig::Terminal::Columns.width(led) <= limit ? led : first, *rest]
  end

  # @rbs units: Array[String]
  # @rbs limit: Integer
  # @rbs separator: String
  # @rbs return: Array[String]
  def pack(units, limit, separator)
    units.each_with_object([]) do |unit, lines|
      joined = "#{lines.last}#{separator}#{unit}"
      if lines.empty? || Riffer::Rig::Terminal::Columns.width(joined) > limit
        lines << unit
      else
        lines[-1] = joined
      end
    end
  end

  # @rbs lines: Array[String]
  # @rbs return: String
  def indented(lines)
    lines.map { |line| "#{' ' * @indent}#{line}\n" }.join
  end

  # @rbs return: Integer?
  def usable_width
    width = @width
    [width - @indent, 1].max if width
  end
end
