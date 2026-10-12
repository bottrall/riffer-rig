# frozen_string_literal: true

require 'test_helper'
require_relative '../support/key_pty'

describe 'editing a line typed into a terminal' do
  before do
    @pty = KeyPty.new
  end

  after do
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
