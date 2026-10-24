# frozen_string_literal: true

module Riffer::Rig::Terminal::Markdown::Flow
  extend self

  PAINTER = Riffer::Rig::Terminal::Painter.new(
    same: lambda do |left, right|
      left.same_style?(right)
    end #: ^(Riffer::Rig::Terminal::Markdown::Span, Riffer::Rig::Terminal::Markdown::Span) -> bool
  ) #: Riffer::Rig::Terminal::Painter[Riffer::Rig::Terminal::Markdown::Span]

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
    owners = spans.flat_map { |span| [span] * span.text.scan(Riffer::Rig::Terminal::Painter::VISIBLE).size }
    sizes = wrapped.map { |line| line.scan(Riffer::Rig::Terminal::Painter::VISIBLE).size }
    starts = sizes.each_with_object([0]) { |size, sums| sums << (sums.fetch(-1) + size) }
    wrapped.each_with_index.map do |line, index|
      PAINTER.paint(line, owners.slice(starts.fetch(index), sizes.fetch(index)) || []) do |text, span|
        style(text, span, theme)
      end
    end
  end

  private

  # @rbs text: String
  # @rbs span: Riffer::Rig::Terminal::Markdown::Span?
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: String
  def style(text, span, theme)
    return text unless span

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
