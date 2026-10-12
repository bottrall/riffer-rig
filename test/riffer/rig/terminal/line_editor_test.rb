# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/key_pty'

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
    assert_equal 'one␊two␛', editor([:paste, "one\ntwo\e"]).printable_before
  end

  it 'prints control characters after the cursor as one-column pictures' do
    assert_equal '␉a␡', editor([:paste, "\ta\u007f"], :home).printable_after
  end

  it 'prints C1 control characters before the cursor as placeholders' do
    assert_equal 'a␦␦␦b', editor([:paste, "a\u0080\u009b\u009fb"]).printable_before
  end

  it 'prints C1 control characters after the cursor as placeholders' do
    assert_equal 'a␦␦␦b', editor([:paste, "a\u0080\u009b\u009fb"], :home).printable_after
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

  it 'deletes the character before the cursor on Backspace' do
    assert_equal 'ac', editor(:left, :backspace, from: typed('abc')).text
  end

  it 'ignores Backspace at the start' do
    assert_equal 'abc', editor(:home, :backspace, from: typed('abc')).text
  end

  it 'deletes a multi-codepoint grapheme as one character' do
    assert_equal 'a', editor(:backspace, from: typed('a👍🏽')).text
  end

  it 'deletes the character under the cursor on Delete' do
    assert_equal 'ac', editor(:home, :right, :delete, from: typed('abc')).text
  end

  it 'ignores Delete at the end' do
    assert_equal 'abc', editor(:delete, from: typed('abc')).text
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

  it 'moves the cursor right' do
    assert_equal 'ab', editor(:home, :right, :right, from: typed('abc')).before
  end

  it 'stays at the end when moving right past it' do
    assert_equal 'a', editor(:right, from: typed('a')).before
  end

  it 'moves the cursor to the start on Home' do
    assert_equal 'abc', editor(:home, from: typed('abc')).after
  end

  it 'moves the cursor to the end on End' do
    assert_equal 'abc', editor(:home, :end, from: typed('abc')).before
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

    it 'keeps earlier history' do
      first = typed('one').submit

      assert_equal %w[one two], editor('t', 'w', 'o', from: first).submit.history
    end

    it 'keeps a blank line out of the history' do
      assert_empty typed('  ').submit.history
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

  describe 'through a pty' do
    def setup
      @pty = KeyPty.new
    end

    def teardown
      @pty.close
    end

    def edit(bytes, from: Riffer::Rig::Terminal::LineEditor.new)
      @pty.type(bytes)
      @pty.keys_until(:enter).reduce(from) { |state, key| state.press(key) }
    end

    def paint(status, state)
      "\e[H\e[2K#{status}\r\n\e[2K#{state.printable_before}#{state.printable_after}\r#{state.printable_before}"
    end

    def edit_under_status(first, *rest)
      @pty.type(first)
      @pty.keys_until(:enter).each_with_index.reduce(Riffer::Rig::Terminal::LineEditor.new) do |state, (key, tick)|
        @pty.type(rest.fetch(tick, ''))
        state.press(key).tap { |pressed| @pty.print(paint("tick #{tick + 1}", pressed)) }
      end
    end

    def frame(status, line, before)
      "\e[2K#{status}\r\n\e[2K#{line}\r#{before}"
    end

    it 'moves the cursor with arrows, Home and End' do
      assert_equal 'aXbYcZ', edit("abc\e[H\e[CX\e[FZ\e[D\e[DY\r").text
    end

    it 'edits with Backspace and Delete' do
      assert_equal 'ad', edit("abcd\e[D\x7f\e[D\e[3~\r").text
    end

    it 'recalls history with Up and Down' do
      past = edit("second\r", from: edit("first\r").submit).submit

      assert_equal 'first!', edit("draft\e[A\e[A\e[A\e[B\e[A!\r", from: past).text
    end

    it 'inserts a bracketed paste at the cursor' do
      assert_equal "aone\ntwob", edit("ab\e[D\e[200~one\ntwo\e[201~\r").text
    end

    it 'loses no keystrokes typed between rewrites of a status line above the input line' do
      assert_equal 'hello', edit_under_status('he', 'l', "o\e[D", 'l', "\r").text
    end

    it 'leaves the status line and the input line intact in every rewrite' do
      edit_under_status('he', 'l', "o\e[D", 'l', "\r")
      rewrites = [
        frame('tick 1', 'h', 'h'), frame('tick 2', 'he', 'he'), frame('tick 3', 'hel', 'hel'),
        frame('tick 4', 'helo', 'helo'), frame('tick 5', 'helo', 'hel'), frame('tick 6', 'hello', 'hell')
      ]

      assert_equal rewrites, @pty.output.split("\e[H").drop(1)
    end
  end
end
