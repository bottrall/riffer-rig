# frozen_string_literal: true

require 'test_helper'

class Riffer::Rig::UI::UnstableTailTest < Minitest::Test
  SPLIT = Riffer::Rig::UI::Markdown::UnstableTail

  def test_stable_source_returns_itself_as_prefix
    assert_equal ['Hello world', ''], SPLIT.split('Hello world')
  end

  def test_empty_source_splits_to_empty
    # split('') is the two-element ['', ''] contract under test; chars reads as
    # character iteration and would obscure it.
    assert_equal ['', ''], SPLIT.split('') # rubocop:disable Style/StringChars
  end

  def test_odd_double_asterisks_are_held_raw
    assert_equal ['Hello ', '**bo'], SPLIT.split('Hello **bo')
  end

  def test_even_double_asterisks_are_stable
    assert_equal ['Hello **bo**', ''], SPLIT.split('Hello **bo**')
  end

  def test_odd_backticks_are_held_raw
    assert_equal ['code ', '`x'], SPLIT.split('code `x')
  end

  def test_even_backticks_are_stable
    assert_equal ['code `x`', ''], SPLIT.split('code `x`')
  end

  def test_open_fence_holds_fence_and_body_raw
    source = "done\n```ruby\nputs 1\n"
    prefix, tail = SPLIT.split(source)

    assert_equal ["done\n", "```ruby\nputs 1\n"], [prefix, tail]
  end

  def test_closed_fence_is_stable
    assert_equal ["```ruby\nputs 1\n```\n", ''], SPLIT.split("```ruby\nputs 1\n```\n")
  end

  def test_tilde_fence_is_detected
    source = "text\n~~~\ncode\n"
    prefix, tail = SPLIT.split(source)

    assert_equal ["text\n", "~~~\ncode\n"], [prefix, tail]
  end
end
