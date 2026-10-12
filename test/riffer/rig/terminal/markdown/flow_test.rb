# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Markdown::Flow do
  def span(text, styles: [], url: nil)
    Riffer::Rig::Terminal::Markdown::Span.new(text: text, styles: styles, url: url)
  end

  def lines(spans, enabled: true, width: 40)
    theme = Riffer::Rig::Terminal::Theme.new(enabled: enabled)
    Riffer::Rig::Terminal::Markdown::Flow.lines(spans, theme: theme, width: width)
  end

  it 'leaves unstyled text unpainted' do
    assert_equal ['hello there'], lines([span('hello there')])
  end

  it 'wraps at the width' do
    assert_equal %w[hello there], lines([span('hello there')], width: 8)
  end

  it 'collapses runs of spaces' do
    assert_equal ['a b'], lines([span('  a    b ')])
  end

  it 'returns one empty line for no spans' do
    assert_equal [''], lines([])
  end

  it 'paints a styled span' do
    assert_equal ["a \e[1mb\e[0m"], lines([span('a '), span('b', styles: [:bold])])
  end

  it 'paints the spaces inside a styled span' do
    assert_equal ["\e[1mb c\e[0m"], lines([span('b c', styles: [:bold])])
  end

  it 'leaves the space between two styles unpainted' do
    assert_equal ["\e[1ma\e[0m \e[3mb\e[0m"], lines([span('a ', styles: [:bold]), span('b', styles: [:italic])])
  end

  it 'joins neighbouring spans of one style into one run' do
    assert_equal ["\e[1ma*b\e[0m"], lines([span('a', styles: [:bold]), span('*b', styles: [:bold])])
  end

  it 'closes and reopens a style across a wrap' do
    assert_equal ["\e[1mhello\e[0m", "\e[1mthere\e[0m"], lines([span('hello there', styles: [:bold])], width: 8)
  end

  it 'paints a word split across two styles without a space' do
    assert_equal ["\e[1mb\e[0m,"], lines([span('b', styles: [:bold]), span(',')])
  end

  it 'layers the styles of a span' do
    assert_equal ["\e[3m\e[1mb\e[0m\e[0m"], lines([span('b', styles: %i[bold italic])])
  end

  it 'paints code' do
    assert_equal ["\e[38;2;45;226;230mb\e[0m"], lines([span('b', styles: [:code])])
  end

  it 'paints a heading' do
    assert_equal ["\e[1m\e[38;2;122;92;255mb\e[0m\e[0m"], lines([span('b', styles: [:heading])])
  end

  it 'wraps a linked run in an osc 8 hyperlink' do
    assert_equal(
      ["\e]8;;https://example.com\e\\\e[4m\e[38;2;77;124;255mb\e[0m\e[0m\e]8;;\e\\"],
      lines([span('b', url: 'https://example.com')])
    )
  end

  it 'paints nothing when the theme is disabled' do
    assert_equal ['a b'], lines([span('a ', styles: [:bold]), span('b', url: 'https://example.com')], enabled: false)
  end

  it 'hard-splits a word longer than the width and keeps its style' do
    assert_equal ["\e[1mabcd\e[0m", "\e[1mef\e[0m"], lines([span('abcdef', styles: [:bold])], width: 4)
  end
end
