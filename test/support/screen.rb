# frozen_string_literal: true

class Screen
  SEQUENCE = /\e\[([\d;]*)([A-Za-z])|[\r\n]|./m
  PARTIAL_SEQUENCE = /\e(\[[\d;]*)?\z/n

  attr_reader :row, :column, :scrollback
  attr_writer :columns

  def initialize(rows:, columns:)
    @height = rows
    @columns = columns
    @rows = ['']
    @scrollback = []
    @row = 0
    @column = 0
    @pending = ''.b
  end

  def rows
    @rows.map(&:rstrip)
  end

  # A pty read can end partway through an escape sequence or a multibyte
  # character; the rest arrives with the next write.
  def write(bytes)
    text = @pending + bytes.b
    complete = whole(text.delete_suffix(text[PARTIAL_SEQUENCE].to_s))
    @pending = text.byteslice(complete.bytesize..)
    complete.force_encoding(Encoding::UTF_8).scan(SEQUENCE) { apply(Regexp.last_match) }
  end

  private

  def whole(text)
    (0..[3, text.bytesize].min).map { |trim| text.byteslice(0, text.bytesize - trim) }
                               .find { |head| head.dup.force_encoding(Encoding::UTF_8).valid_encoding? } || text
  end

  def apply(match)
    return control(match[2], [match[1].to_i, 1].max) if match[2]

    case match[0]
    when "\r" then @column = 0
    # Raw mode: a line feed moves down without returning the carriage.
    when "\n" then line_feed
    else put(match[0])
    end
  end

  def control(final, count)
    case final
    when 'A' then @row -= count
    when 'G' then @column = count - 1
    when 'J' then erase
    when 'm' then nil
    else raise "unsupported control sequence #{final}"
    end
  end

  def erase
    @rows = @rows.first(@row + 1)
    @rows[@row] = @rows[@row][0, @column].to_s
  end

  def line_feed
    @row += 1
    @rows << '' if @row == @rows.size
    return unless @rows.size > @height

    @scrollback << @rows.shift.rstrip
    @row -= 1
  end

  def put(char)
    if @column == @columns
      @column = 0
      line_feed
    end
    @rows[@row] = @rows[@row].ljust(@column)
    @rows[@row][@column] = char
    @column += 1
  end
end
