# frozen_string_literal: true

module Riffer::Rig::Terminal::Markdown::Blocks
  extend self

  FENCE = /\A(?<indent> {0,3})(?<fence>`{3,}|~{3,})\s*(?<language>[^\s`]*)[^`]*\z/ #: Regexp

  HEADING = /\A {0,3}(?<marks>\#{1,6})(?:\s+(?<title>.*?))?(?:\s+\#+)?\s*\z/ #: Regexp

  RULE = /\A {0,3}(?:(?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,})\z/ #: Regexp

  QUOTE = /\A {0,3}> ?/ #: Regexp

  MARKER = /[-*+]|\d{1,9}[.)]/ #: Regexp

  ITEM = /\A {0,3}(?:#{MARKER})(?: |\z)/ #: Regexp

  DIVIDER = /\A\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*\z/ #: Regexp

  # @rbs lines: Array[String]
  # @rbs return: Array[Array[String]]
  def split(lines)
    starts = Enumerator.produce(0) { |start| boundary(lines, start) }.take_while { |start| start < lines.size }
    [*starts, lines.size].each_cons(2).map { |from, to| lines.slice(from...to) || [] }
  end

  # @rbs lines: Array[String]
  # @rbs index: Integer
  # @rbs return: Symbol
  def kind(lines, index)
    line = lines.fetch(index)
    if line.strip.empty? then :blank
    elsif FENCE.match?(line) then :fence
    elsif HEADING.match?(line) then :heading
    elsif RULE.match?(line) then :rule
    elsif QUOTE.match?(line) then :quote
    elsif ITEM.match?(line) then :list
    elsif table?(lines, index) then :table
    else
      :paragraph
    end
  end

  # @rbs fence: String
  # @rbs return: Regexp
  def closing(fence)
    /\A {0,3}#{Regexp.escape(fence)}#{Regexp.escape(fence[0].to_s)}*\s*\z/
  end

  private

  # @rbs lines: Array[String]
  # @rbs start: Integer
  # @rbs return: Integer
  def boundary(lines, start)
    kind = kind(lines, start)
    case kind
    when :heading, :rule then start + 1
    when :fence then fence_boundary(lines, start)
    when :table then extend_while(lines, start + 2) { |index| lines.fetch(index).include?('|') }
    when :list then extend_while(lines, start + 1) { |index| list_line?(lines.fetch(index)) }
    else extend_while(lines, start + 1) { |index| kind(lines, index) == kind }
    end
  end

  # @rbs lines: Array[String]
  # @rbs from: Integer
  # @rbs &block: (Integer) -> bool
  # @rbs return: Integer
  def extend_while(lines, from, &)
    (from...lines.size).find { |index| !yield(index) } || lines.size
  end

  # @rbs lines: Array[String]
  # @rbs start: Integer
  # @rbs return: Integer
  def fence_boundary(lines, start)
    closing = closing(lines.fetch(start)[FENCE, :fence].to_s)
    close = (start.succ...lines.size).find { |index| closing.match?(lines.fetch(index)) }
    close ? close + 1 : lines.size
  end

  # @rbs line: String
  # @rbs return: bool
  def list_line?(line)
    line.strip.empty? || line.start_with?('  ') || ITEM.match?(line)
  end

  # @rbs lines: Array[String]
  # @rbs index: Integer
  # @rbs return: bool
  def table?(lines, index)
    divider = lines[index + 1]
    !divider.nil? && lines.fetch(index).include?('|') && divider.include?('|') && DIVIDER.match?(divider)
  end
end
