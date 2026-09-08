# frozen_string_literal: true

require 'test_helper'

class Riffer::Rig::UI::WalkerTest < Minitest::Test
  def setup
    @theme = Riffer::Rig::UI::Theme.new(enabled: false)
    @highlighter = Riffer::Rig::UI::Markdown::Highlighter.new(@theme)
  end

  def render(source, width: 60)
    Riffer::Rig::UI::Markdown::Walker.render(source, width:, theme: @theme, highlighter: @highlighter)
  end

  def test_empty_source_renders_no_lines
    assert_empty render('')
  end

  def test_paragraph_text_renders_plain
    assert_equal ['plain text'], render('plain text')
  end

  def test_inline_emphasis_markers_drop_when_theme_disabled
    assert_equal ['bold and em'], render('**bold** and *em*')
  end

  def test_heading_renders_upcased_without_marker
    assert_equal ['MY TITLE'], render('# my title')
  end

  def test_second_level_heading_keeps_case
    assert_equal ['Sub Title'], render('## Sub Title')
  end

  def test_unordered_list_uses_bullets
    assert_equal ['• one', '• two'], render("- one\n- two")
  end

  def test_nested_list_is_indented
    assert_equal ['• one', '• two', '  • nested'], render("- one\n- two\n  - nested")
  end

  def test_ordered_list_uses_numbers
    assert_equal ['1. first', '2. second'], render("1. first\n2. second")
  end

  def test_blockquote_gets_a_bar_prefix
    assert_equal ['▌ quoted'], render('> quoted')
  end

  def test_codeblock_renders_indented_with_language_label
    assert_equal ['── ruby', '  puts 1'], render("```ruby\nputs 1\n```")
  end

  def test_codeblock_without_language_renders_indented_only
    assert_equal ['  puts 1'], render("```\nputs 1\n```")
  end

  def test_table_renders_piped_columns
    assert_equal ['a │ b', '1 │ 2'], render("| a | b |\n|---|---|\n| 1 | 2 |")
  end

  def test_horizontal_rule_fills_the_width
    assert_equal ['─' * 40], render('---', width: 40)
  end

  def test_long_paragraph_hard_wraps_to_width
    lines = render('word ' * 30, width: 20)

    assert(lines.length > 1 && lines.all? { |line| line.length <= 20 })
  end

  def test_unstable_tail_streams_raw
    assert_equal ['Hello', '**bo'], render('Hello **bo')
  end

  def test_link_renders_label_with_url
    assert_equal ['label (http://x.com)'], render('[label](http://x.com)')
  end

  def test_inline_code_keeps_value
    assert_equal ['run x now'], render('run `x` now')
  end
end
