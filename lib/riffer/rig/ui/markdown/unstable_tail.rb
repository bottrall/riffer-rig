# frozen_string_literal: true

module Riffer::Rig::UI::Markdown::UnstableTail
  extend self

  # Splits accumulated markdown source into a stable prefix and a raw tail.
  FENCE_OPEN = /\A {0,3}(`{3,}|~{3,})/ #: Regexp
  PAIRED_MARKERS = ['**', '~~'].freeze #: Array[String]

  # The tail is raw in the frame so half-typed syntax never renders as
  # formatting and snaps back: an open fence would close itself, a lone `*`
  # would italicize. It joins the parse once stable.
  #
  # @rbs source: String
  # @rbs return: [String, String]
  def split(source)
    fence = open_fence_source(source)
    return fence if fence

    emphasis = trailing_open_emphasis(source)
    return [source, ''] unless emphasis

    [source[0, source.rindex(emphasis) || 0] || '', source[source.rindex(emphasis)..] || '']
  end

  # @rbs source: String
  # @rbs return: [String, String]?
  def open_fence_source(source)
    open = nil # : String?
    source.each_line do |line|
      if open
        open = nil if line.match?(/\A {0,3}#{Regexp.escape(open)}{3,}\s*\z/)
      elsif (match = line.match(FENCE_OPEN))
        open = match[1][0]
      end
    end
    return nil unless open

    start = source.rindex(/\n? {0,3}#{Regexp.escape(open)}{3,}/) || 0 # : Integer
    head = source[0, start] || '' # : String
    tail = source[start..] || '' # : String
    [head, tail]
  end

  # @rbs source: String
  # @rbs return: String?
  def trailing_open_emphasis(source)
    paragraph = source.split("\n\n", -1).last.to_s
    PAIRED_MARKERS.each do |marker|
      count = paragraph.scan(marker).length
      return marker if count.odd?
    end
    return '`' if paragraph.count('`').odd?

    singles = paragraph.scan(/(?<!\*)\*(?!\*)/)
    singles.length.odd? ? '*' : nil
  end
end
