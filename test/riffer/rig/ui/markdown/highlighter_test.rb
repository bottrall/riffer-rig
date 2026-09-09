# frozen_string_literal: true

require 'test_helper'

class Riffer::Rig::UI::HighlighterTest < Minitest::Test
  def test_unknown_language_returns_source_unstyled
    assert_equal 'puts 1', highlighter.highlight('puts 1', 'nosuchlang')
  end

  def test_nil_language_returns_source_unstyled
    assert_equal 'puts 1', highlighter.highlight('puts 1', nil)
  end

  def test_known_language_preserves_the_source_text
    result = highlighter.highlight("def foo\nend", 'ruby')

    assert_equal "def foo\nend", result.gsub(/\e\[[0-9;]*m/, '')
  end

  def test_known_language_applies_theme_styling_when_enabled
    enabled = Riffer::Rig::UI::Markdown::Highlighter.new(Riffer::Rig::UI::Theme.new(enabled: true))

    assert_match(/\e\[38;2;/, enabled.highlight('def', 'ruby'))
  end

  def test_tabs_are_expanded
    assert_equal '  puts 1', highlighter.highlight("\tputs 1", 'ruby')
  end

  private

  def highlighter
    Riffer::Rig::UI::Markdown::Highlighter.new(Riffer::Rig::UI::Theme.new(enabled: false))
  end
end
