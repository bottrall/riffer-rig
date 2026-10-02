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
    @line = +''
  end

  # @rbs text: String
  # @rbs return: String
  def <<(text)
    @line << text
    out = +''
    while (logical = take_line)
      out << physical_lines(logical)
    end
    out
  end

  # @rbs return: String
  def flush
    out = +''
    out << physical_lines(@line) unless @line.strip.empty?
    @line = +''
    out
  end

  private

  # @rbs return: String?
  def take_line
    if (index = @line.index("\n"))
      @line.slice!(0, index + 1).to_s.chomp
    elsif overfull?
      take_overfull_head
    end
  end

  # @rbs return: bool
  def overfull?
    width = @width
    return false unless width

    @line.length > width - @indent
  end

  # @rbs return: String
  def take_overfull_head
    limit = (@width || 0) - @indent
    head = @line[0, limit].to_s
    if (space = head.rindex(' '))
      @line.slice!(0, space + 1)
      head[0, space].to_s
    else
      @line.slice!(0, limit).to_s
    end
  end

  # @rbs logical: String
  # @rbs return: String
  def physical_lines(logical)
    return "\n" if logical.empty?

    wrap_words(logical).map { |line| "#{indent}#{line}\n" }.join
  end

  # @rbs return: String
  def indent
    ' ' * @indent
  end

  # @rbs text: String
  # @rbs return: Array[String]
  def wrap_words(text)
    width = @width
    limit = width ? width - @indent : nil
    return [text] unless limit

    out = [] #: Array[String]
    current = nil #: String?
    text.split.each do |word|
      if current
        if current.length + 1 + word.length <= limit
          current = "#{current} #{word}"
          next
        end
        out << current
      end
      out << word.slice!(0, limit).to_s while word.length > limit
      current = word unless word.empty?
    end
    out << current if current
    out
  end
end
