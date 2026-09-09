# frozen_string_literal: true

module Riffer::Rig::UI::Markdown::UnstableTail
  extend self

  # Splits accumulated markdown source into a stable prefix and a raw tail.
  FENCE_OPEN = /\A {0,3}(`{3,}|~{3,})/
  PAIRED_MARKERS = ['**', '~~'].freeze

  # The tail is raw in the frame so half-typed syntax never renders as
  # formatting and snaps back: an open fence would close itself, a lone `*`
  # would italicize. It joins the parse once stable.
  def split(source)
    fence = open_fence_source(source)
    return fence if fence

    emphasis = trailing_open_emphasis(source)
    return [source, ''] unless emphasis

    [source[0, source.rindex(emphasis) || 0], source[source.rindex(emphasis)..]]
  end

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

    start = source.rindex(/\n? {0,3}#{Regexp.escape(open)}{3,}/) # : Integer?
    [source[0, start], source[start..]] # : [String, String]
  end

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
