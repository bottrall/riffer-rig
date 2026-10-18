# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::LineEditor do
  def editor(*keys, from: Riffer::Rig::Terminal::LineEditor.new)
    keys.reduce(from) { |state, key| state.press(key(*key)) }
  end

  def key(name, text = nil)
    return Riffer::Rig::Terminal::Key.new(:text, name) if name.is_a?(String)

    Riffer::Rig::Terminal::Key.new(name, text)
  end

  def typed(text)
    editor(*text.chars)
  end

  def large
    "diff\n#{'x' * 4195}"
  end

  it 'starts empty' do
    assert_equal '', editor.text
  end

  it 'is frozen' do
    assert_predicate editor, :frozen?
  end

  it 'returns a new editor instead of changing the pressed one' do
    original = typed('a')
    original.press(key('b'))

    assert_equal 'a', original.text
  end

  it 'prints control characters before the cursor as one-column pictures' do
    assert_equal 'one␉two␛', editor([:paste, "one\ttwo\e"]).printable_before
  end

  it 'prints a line break before the cursor as a line break' do
    assert_equal "one\ntwo", editor([:paste, "one\ntwo"]).printable_before
  end

  it 'prints C1 control characters before the cursor as placeholders' do
    assert_equal 'a␦␦␦b', editor([:paste, "a\u0080\u009b\u009fb"]).printable_before
  end

  it 'drops a cursor sentinel pasted before the cursor' do
    assert_equal 'ab', editor([:paste, "a\uE000b"]).printable_before
  end

  it 'prints control characters after the cursor as one-column pictures' do
    assert_equal '␉a␡', editor([:paste, "\ta\u007f"], :home).printable_after
  end

  it 'prints C1 control characters after the cursor as placeholders' do
    assert_equal 'a␦␦␦b', editor([:paste, "a\u0080\u009b\u009fb"], :home).printable_after
  end

  it 'prints a paste under the elision size in full' do
    assert_equal 'x' * 999, editor([:paste, 'x' * 999]).printable_before
  end

  it 'elides a large paste before the cursor' do
    assert_equal 'a[pasted 4.2k chars]b', editor('a', [:paste, large], 'b').printable_before
  end

  it 'elides a large paste after the cursor' do
    assert_equal '[pasted 4.2k chars]b', editor([:paste, large], 'b', :home).printable_after
  end

  it 'elides a paste that begins with an earlier large paste as one' do
    longer = "#{large}#{'y' * 1800}"

    assert_equal '[pasted 6.0k chars]', editor([:paste, large], :backspace, [:paste, longer]).printable_before
  end

  it 'inserts typed characters' do
    assert_equal 'abc', typed('abc').text
  end

  it 'keeps the cursor after the typed characters' do
    assert_equal 'abc', typed('abc').before
  end

  it 'inserts at the cursor' do
    assert_equal 'abc', editor(:left, 'b', from: typed('ac')).text
  end

  it 'inserts a paste at the cursor' do
    assert_equal 'a12b', editor(:left, [:paste, '12'], from: typed('ab')).text
  end

  it 'inserts a multi-line paste literally' do
    assert_equal "one\ntwo", editor([:paste, "one\ntwo"]).text
  end

  it 'inserts a line break at the cursor on Ctrl-J' do
    assert_equal "a\nb", editor('a', :newline, 'b').text
  end

  it 'inserts a line break at the cursor on Alt-Enter' do
    assert_equal "a\nb", editor('a', :alt_enter, 'b').text
  end

  it 'keeps an elided paste whole in the text' do
    assert_equal "a#{large}b", editor('a', [:paste, large], 'b').text
  end

  it 'deletes the character before the cursor on Backspace' do
    assert_equal 'ac', editor(:left, :backspace, from: typed('abc')).text
  end

  it 'ignores Backspace at the start' do
    assert_equal 'abc', editor(:home, :backspace, from: typed('abc')).text
  end

  it 'deletes a multi-codepoint grapheme as one character' do
    assert_equal 'a', editor(:backspace, from: typed('a👍🏽')).text
  end

  it 'deletes an elided paste before the cursor as one unit' do
    assert_equal 'ab', editor('a', [:paste, large], :backspace, 'b').text
  end

  it 'deletes the character under the cursor on Delete' do
    assert_equal 'ac', editor(:home, :right, :delete, from: typed('abc')).text
  end

  it 'ignores Delete at the end' do
    assert_equal 'abc', editor(:delete, from: typed('abc')).text
  end

  it 'deletes an elided paste under the cursor as one unit' do
    assert_equal 'ab', editor('a', [:paste, large], 'b', :home, :right, :delete).text
  end

  it 'moves the cursor left' do
    assert_equal 'ab', editor(:left, from: typed('abc')).before
  end

  it 'stays at the start when moving left past it' do
    assert_equal 'a', editor(:left, :left, from: typed('a')).after
  end

  it 'moves over a multi-codepoint grapheme as one character' do
    assert_equal 'a', editor(:left, from: typed('a👍🏽')).before
  end

  it 'moves left over an elided paste as one unit' do
    assert_equal 'a', editor('a', [:paste, large], :left).before
  end

  it 'moves the cursor right' do
    assert_equal 'ab', editor(:home, :right, :right, from: typed('abc')).before
  end

  it 'stays at the end when moving right past it' do
    assert_equal 'a', editor(:right, from: typed('a')).before
  end

  it 'moves right over an elided paste as one unit' do
    assert_equal 'b', editor([:paste, large], 'b', :home, :right).after
  end

  it 'moves to the start of the word on Ctrl-Left' do
    assert_equal 'foo ', editor(:ctrl_left, from: typed('foo bar')).before
  end

  it 'moves to the start of the word on Alt-Left' do
    assert_equal 'foo ', editor(:alt_left, from: typed('foo bar')).before
  end

  it 'moves to the start of the word on Alt-B' do
    assert_equal 'foo ', editor(:alt_b, from: typed('foo bar')).before
  end

  it 'skips the punctuation before a word when moving a word left' do
    assert_equal 'foo.', editor(:ctrl_left, :ctrl_left, from: typed('foo.bar(baz)')).before
  end

  it 'stays at the start when moving a word left past it' do
    assert_equal 'foo', editor(:ctrl_left, :ctrl_left, from: typed('foo')).after
  end

  it 'moves a word left over multi-codepoint graphemes whole' do
    assert_equal 'a ', editor(:ctrl_left, from: typed("a cafe\u0301 👍🏽")).before
  end

  it 'moves to the end of the word on Ctrl-Right' do
    assert_equal 'foo', editor(:home, :ctrl_right, from: typed('foo bar')).before
  end

  it 'moves to the end of the word on Alt-Right' do
    assert_equal 'foo', editor(:home, :alt_right, from: typed('foo bar')).before
  end

  it 'moves to the end of the word on Alt-F' do
    assert_equal 'foo', editor(:home, :alt_f, from: typed('foo bar')).before
  end

  it 'skips the punctuation before a word when moving a word right' do
    assert_equal 'foo.bar(baz', editor(:home, :ctrl_right, :ctrl_right, :ctrl_right, from: typed('foo.bar(baz)')).before
  end

  it 'stays at the end when moving a word right past it' do
    assert_equal 'foo', editor(:ctrl_right, from: typed('foo')).before
  end

  it 'moves a word right over multi-codepoint graphemes whole' do
    assert_equal ' b', editor(:home, :ctrl_right, from: typed("👍🏽 cafe\u0301 b")).after
  end

  it 'moves the cursor to the start on Home' do
    assert_equal 'abc', editor(:home, from: typed('abc')).after
  end

  it 'moves the cursor to the end on End' do
    assert_equal 'abc', editor(:home, :end, from: typed('abc')).before
  end

  it 'kills the word before the cursor on Ctrl-W' do
    assert_equal 'foo ', editor(:ctrl_w, from: typed('foo bar')).text
  end

  it 'kills the whitespace between the word and the cursor on Ctrl-W' do
    assert_equal 'foo ', editor(:ctrl_w, from: typed('foo bar  ')).text
  end

  it 'kills punctuation as part of the word on Ctrl-W' do
    assert_equal 'a ', editor(:ctrl_w, from: typed('a foo.bar(baz)')).text
  end

  it 'keeps the text after the cursor on Ctrl-W' do
    assert_equal 'foo r', editor(:left, :ctrl_w, from: typed('foo bar')).text
  end

  it 'kills a multi-codepoint grapheme whole on Ctrl-W' do
    assert_equal 'a ', editor(:ctrl_w, from: typed('a 👍🏽')).text
  end

  it 'ignores Ctrl-W at the start' do
    assert_equal 'abc', editor(:home, :ctrl_w, from: typed('abc')).text
  end

  it 'kills to the start of the line on Ctrl-U' do
    assert_equal 'c', editor(:left, :ctrl_u, from: typed('a bc')).text
  end

  it 'kills to the end of the line on Ctrl-K' do
    assert_equal 'a', editor(:home, :right, :ctrl_k, from: typed('a bc')).text
  end

  it 'ignores Ctrl-K at the end' do
    assert_equal 'abc', editor(:ctrl_k, from: typed('abc')).text
  end

  it 'yanks the word Ctrl-W killed at the cursor' do
    assert_equal 'barfoo ', editor(:ctrl_w, :home, :ctrl_y, from: typed('foo bar')).text
  end

  it 'yanks the text Ctrl-U killed at the cursor' do
    assert_equal 'ca b', editor(:left, :ctrl_u, :end, :ctrl_y, from: typed('a bc')).text
  end

  it 'yanks the text Ctrl-K killed at the cursor' do
    assert_equal ' bca', editor(:home, :right, :ctrl_k, :home, :ctrl_y, from: typed('a bc')).text
  end

  it 'leaves the cursor after the yanked text' do
    assert_equal 'bar', editor(:ctrl_w, :home, :ctrl_y, from: typed('foo bar')).before
  end

  it 'yanks the same text again on a repeated Ctrl-Y' do
    assert_equal 'abcabc', editor(:ctrl_u, :ctrl_y, :ctrl_y, from: typed('abc')).text
  end

  it 'yanks only the latest kill' do
    assert_equal 'foo ', editor(:ctrl_w, :ctrl_w, :ctrl_y, from: typed('foo bar')).text
  end

  it 'keeps the killed text when Ctrl-W has nothing to kill' do
    assert_equal 'abc', editor(:ctrl_u, :ctrl_w, :ctrl_y, from: typed('abc')).text
  end

  it 'keeps the killed text when Ctrl-K has nothing to kill' do
    assert_equal 'abc', editor(:ctrl_u, :ctrl_k, :ctrl_y, from: typed('abc')).text
  end

  it 'ignores Ctrl-Y before anything is killed' do
    assert_equal 'abc', editor(:ctrl_y, from: typed('abc')).text
  end

  it 'ignores keys it does not edit with' do
    assert_equal 'abc', editor(:tab, :ctrl_c, :enter, from: typed('abc')).text
  end

  describe 'submit' do
    it 'clears the line' do
      assert_equal '', typed('abc').submit.text
    end

    it 'records the line in the history' do
      assert_equal %w[abc], typed('abc').submit.history
    end

    it 'records the line sent in place of the typed one' do
      assert_equal %w[xyz], typed('abc').submit('xyz').history
    end

    it 'keeps earlier history' do
      first = typed('one').submit

      assert_equal %w[one two], editor('t', 'w', 'o', from: first).submit.history
    end

    it 'records an elided paste whole' do
      assert_equal [large], editor([:paste, large]).submit.history
    end

    it 'keeps a blank line out of the history' do
      assert_empty typed('  ').submit.history
    end

    it 'keeps the killed text for the next line' do
      assert_equal 'abc', editor(:ctrl_y, from: editor(:ctrl_u, from: typed('abc')).submit).text
    end
  end

  describe 'history' do
    def recalled(*keys)
      past = Riffer::Rig::Terminal::LineEditor.new(history: %w[first second])
      editor(*keys, from: past)
    end

    it 'stays on the oldest line when Up runs out' do
      assert_equal 'first', recalled(:up, :up, :up).text
    end

    it 'ignores Down when no line is recalled' do
      assert_equal 'draft', recalled(*'draft'.chars, :down).text
    end

    it 'ignores Up without history' do
      assert_equal 'draft', editor(:up, from: typed('draft')).text
    end

    it 'recalls the latest line on Up' do
      assert_equal 'second', recalled(:up).text
    end

    it 'puts the cursor at the end of a recalled line' do
      assert_equal 'second', recalled(:up).before
    end

    it 'recalls older lines on repeated Up' do
      assert_equal 'first', recalled(:up, :up).text
    end

    it 'returns to newer lines on Down' do
      assert_equal 'second', recalled(:up, :up, :down).text
    end

    it 'restores the line being typed when Down passes the newest' do
      assert_equal 'draft', recalled(*'draft'.chars, :up, :down).text
    end

    it 'leaves the history untouched when a recalled line is edited' do
      assert_equal %w[first second second!], recalled(:up, '!').submit.history
    end

    it 'recalls from the newest line again after a submit' do
      assert_equal 'second!', editor(:up, from: recalled(:up, '!').submit).text
    end
  end
end
