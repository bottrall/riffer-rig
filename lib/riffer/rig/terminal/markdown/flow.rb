# frozen_string_literal: true

module Riffer::Rig::Terminal::Markdown::Flow
  extend self

  UNSTYLED = Riffer::Rig::Terminal::Markdown::Span.new(text: ' ') #: Riffer::Rig::Terminal::Markdown::Span

  # @rbs spans: Array[Riffer::Rig::Terminal::Markdown::Span]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: Array[String]
  def lines(spans, theme:, width:)
    wrapper = Riffer::Rig::Terminal::Wrapper.new(width: width, indent: 0)
    wrapped = (wrapper << "#{spans.map(&:text).join}\n").lines(chomp: true)
    # The Wrapper moves and drops spaces but never a visible character, so the
    # nth visible character of its output is the nth one the spans supplied.
    owners = spans.flat_map { |span| [span] * span.text.count('^ ') }
    sizes = wrapped.map { |line| line.count('^ ') }
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
    owner_at = chars.each_index.reject { |index| chars[index] == ' ' }.zip(owners).to_h
    cells = chars.each_index.map { |index| owner_at[index] || between(owner_at[index - 1], owner_at[index + 1]) }
    runs = chars.zip(cells).chunk_while { |(_, left), (_, right)| left.same_style?(right) }
    runs.map { |run| style(run.map(&:first).join, run.fetch(0).last, theme) }.join
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
