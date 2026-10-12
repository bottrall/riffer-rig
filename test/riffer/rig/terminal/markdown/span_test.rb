# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Markdown::Span do
  def span(**)
    Riffer::Rig::Terminal::Markdown::Span.new(text: 'a', **)
  end

  it 'is frozen' do
    assert_predicate span, :frozen?
  end

  it 'defaults to no styles' do
    assert_empty span.styles
  end

  it 'defaults to no url' do
    assert_nil span.url
  end

  it 'shares a style with a span of the same styles and url' do
    assert span(styles: [:bold], url: 'u').same_style?(span(styles: [:bold], url: 'u'))
  end

  it 'does not share a style with a span of other styles' do
    refute span(styles: [:bold]).same_style?(span(styles: [:italic]))
  end

  it 'does not share a style with a span of another url' do
    refute span(url: 'u').same_style?(span(url: 'v'))
  end
end
