# frozen_string_literal: true

class Riffer::Rig::Terminal::Wrapper
  # @rbs @width: Integer?
  # @rbs @indent: Integer
  # @rbs @line: String

  # @rbs width: Integer?
  # @rbs indent: Integer
  # @rbs return: void
  def initialize(width:, indent:)
    @width = width
    @indent = indent
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
    @line = overflow.empty? ? pending : "#{tail}#{pending[/\s*\z/]}"
    [*terminated.map { |line| line.strip.empty? ? "\n" : indented(wrap(line)) }, indented(overflow)].join
  end

  # @rbs return: String
  def flush
    pending = @line
    @line = ''
    pending.strip.empty? ? '' : indented(wrap(pending))
  end

  private

  # @rbs text: String
  # @rbs return: Array[String]
  def wrap(text)
    limit = usable_width
    return [text] unless limit

    pieces = words(text, limit).flat_map do |word|
      Riffer::Rig::Terminal::Columns.width(word) > limit ? pack(word.grapheme_clusters, limit, '') : [word]
    end
    pack(pieces, limit, ' ')
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
