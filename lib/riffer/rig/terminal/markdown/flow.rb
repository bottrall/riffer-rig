# frozen_string_literal: true

module Riffer::Rig::Terminal::Markdown::Flow
  extend self

  UNSTYLED = Riffer::Rig::Terminal::Markdown::Span.new(text: ' ') #: Riffer::Rig::Terminal::Markdown::Span
  VISIBLE = /\S/ #: Regexp

  # @rbs spans: Array[Riffer::Rig::Terminal::Markdown::Span]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: Array[String]
  def lines(spans, theme:, width:)
    wrapper = Riffer::Rig::Terminal::Wrapper.new(width: width, indent: 0)
    wrapped = (wrapper << "#{spans.map(&:text).join}\n").lines(chomp: true)
    # The Wrapper moves, drops and rewrites whitespace but never a visible
    # character, so the nth visible character of its output is the nth one the
    # spans supplied.
    owners = spans.flat_map { |span| [span] * span.text.scan(VISIBLE).size }
    sizes = wrapped.map { |line| line.scan(VISIBLE).size }
    starts = sizes.each_with_object([0]) { |size, sums| sums << (sums.fetch(-1) + size) }
    wrapped.each_with_index.map do |line, index|
      paint(line, owners.slice(starts.fetch(index), sizes.fetch(index)) || [], theme)
    end
  end

  private

  # @rbs line: String
  # @rbs owners: Array[Riffer::Rig::Terminal::Markdown::Span]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: String
  def paint(line, owners, theme)
    chars = line.chars
    owner_at = chars.each_index.select { |index| chars.fetch(index).match?(VISIBLE) }.zip(owners).to_h
    slots = chars.each_index.map { |index| owner_at[index] }
    cells = nearest(slots).zip(nearest(slots.reverse).reverse).map { |left, right| between(left, right) }
    runs = cells.zip(chars).chunk_while { |(left, _), (right, _)| left.same_style?(right) }
    runs.map { |run| style(run.map(&:last).join, run.fetch(0).first, theme) }.join
  end

  # @rbs slots: Array[Riffer::Rig::Terminal::Markdown::Span?]
  # @rbs return: Array[Riffer::Rig::Terminal::Markdown::Span?]
  def nearest(slots)
    slots.each_with_object([]) { |slot, filled| filled << (slot || filled.last) }
  end

  # @rbs left: Riffer::Rig::Terminal::Markdown::Span?
  # @rbs right: Riffer::Rig::Terminal::Markdown::Span?
  # @rbs return: Riffer::Rig::Terminal::Markdown::Span
  def between(left, right)
    left && right && left.same_style?(right) ? left : UNSTYLED
  end

  # @rbs text: String
  # @rbs span: Riffer::Rig::Terminal::Markdown::Span
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: String
  def style(text, span, theme)
    styled = span.styles.reduce(text) { |painted, name| apply(painted, name, theme) }
    url = span.url
    url ? theme.link(styled, url) : styled
  end

  # @rbs text: String
  # @rbs name: Symbol
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: String
  def apply(text, name, theme)
    case name
    when :bold then theme.bold(text)
    when :italic then theme.italic(text)
    when :code then theme.code(text)
    else theme.heading(text)
    end
  end
end
