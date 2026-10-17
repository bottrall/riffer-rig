# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Markdown::Table do
  def lines(source, enabled: false, width: nil)
    theme = Riffer::Rig::Terminal::Theme.new(enabled: enabled)
    Riffer::Rig::Terminal::Markdown::Table.lines(source.lines(chomp: true), theme: theme, width: width)
  end

  def past_limit
    ["#{'a' * 496} │ b", "a#{' ' * 495} │", "#{'─' * 496}─┼──"]
  end

  it 'renders a grid as wide as the limit when no width is known' do
    assert_equal ["#{'a' * 496} │ b", "#{'─' * 496}─┼──"], lines("|#{'a' * 496}|b|\n|-|-|")
  end

  it 'wraps a grid to the limit when no width is known' do
    assert_equal past_limit, lines("|#{'a' * 497}|b|\n|-|-|")
  end

  it 'wraps a grid to the limit when the width is past it' do
    assert_equal past_limit, lines("|#{'a' * 497}|b|\n|-|-|", width: 1000)
  end

  it 'reads rows without outer pipes' do
    assert_equal ['a │ b', '──┼──', '1 │ 2'], lines("a | b\n--- | ---\n1 | 2")
  end

  it 'ignores the alignment marks of the divider' do
    assert_equal ['a │ b', '──┼──', '1 │ 2'], lines("| a | b |\n|:--|--:|\n| 1 | 2 |")
  end

  it 'keeps an escaped pipe inside its cell' do
    assert_equal ['a | b │ c', '──────┼──'], lines("| a \\| b | c |\n|---|---|")
  end

  it 'keeps a pipe inside a code span in its cell' do
    assert_equal ['`a|b` │ c', '──────┼──'], lines("| `a|b` | c |\n|---|---|")
  end

  it 'splits at a pipe after an unclosed tick' do
    assert_equal ['`a │ b', '───┼──'], lines("| `a | b |\n|---|---|")
  end

  it 'opens no code span inside an unclosed tick run' do
    assert_equal ['``a │ b`', '────┼───'], lines("| ``a | b` |\n|---|---|")
  end

  it 'opens no code span at an escaped tick' do
    assert_equal ['`a │ b`', '───┼───'], lines("| \\`a | b` |\n|---|---|")
  end

  it 'fills a short row with empty cells' do
    assert_equal ['a │ b', '──┼──', '1 │'], lines("| a | b |\n|---|---|\n| 1 |")
  end

  it 'drops the cells of a row past the header' do
    assert_equal ['a │ b', '──┼──', '1 │ 2'], lines("| a | b |\n|---|---|\n| 1 | 2 | 3 | 4 |")
  end

  it 'renders a header with no rows' do
    assert_equal ['a │ b', '──┼──'], lines("| a | b |\n|---|---|")
  end

  it 'keeps the backticks of a code cell without colour' do
    assert_equal ['a', '───', '`x`'], lines("| a |\n|---|\n| `x` |")
  end

  it 'measures a cell by its visible text' do
    assert_equal ["\e[1ma\e[0m \e[2m│\e[0m \e[1mb\e[0m", "\e[2m──┼──\e[0m", "\e[1mx\e[0m \e[2m│\e[0m y"],
                 lines("| a | b |\n|---|---|\n| **x** | y |", enabled: true)
  end

  it 'pads each column to its widest cell when the grid fits the width' do
    assert_equal ['a    │ b', '─────┼──', 'long │ 2'], lines("| a | b |\n|---|---|\n| long | 2 |", width: 8)
  end

  it 'shrinks only the widest column when that is enough' do
    assert_equal ['a │ b            │ c', '──┼──────────────┼──', 'x │ one two      │ y', '  │ three four   │'],
                 lines("| a | b | c |\n|---|---|---|\n| x | one two three four | y |", width: 20)
  end

  it 'shrinks the widest columns to a common width' do
    assert_equal ['a          │ b', '───────────┼───────────', 'one two    │ four five', 'three      │ six'],
                 lines("| a | b |\n|---|---|\n| one two three | four five six |", width: 23)
  end

  it 'shrinks a column that wraps at spaces before a column of one long word' do
    assert_equal ['a            │ b', '─────────────┼─────────', 'aaaaaaaaaaaa │ one two', '             │ three',
                  '             │ four'],
                 lines("| a | b |\n|---|---|\n| aaaaaaaaaaaa | one two three four |", width: 23)
  end

  it 'breaks a long word once every column has shrunk to its floor' do
    assert_equal ['a          │ b', '───────────┼─────────', 'aaaaaaaaaa │ one two', 'aa         │ three',
                  '           │ four'],
                 lines("| a | b |\n|---|---|\n| aaaaaaaaaaaa | one two three four |", width: 21)
  end

  it 'lays the rows out as records when the columns cannot shrink enough' do
    assert_equal ['a: one two', 'three', 'b: 2', 'c: 3'],
                 lines("| a | b | c |\n|---|---|---|\n| one two three | 2 | 3 |", width: 14)
  end

  it 'draws the separators beside every line of a wrapped row' do
    assert_equal ['a │ b', '──┼──────────', 'x │ one two', '  │ three', '  │ four'],
                 lines("| a | b |\n|---|---|\n| x | one two three four |", width: 13)
  end

  it 'pads a cell with a run of spaces by its printed length' do
    assert_equal ['a  b │ c', '─────┼──', 'd    │ e'], lines("| a  b | c |\n|---|---|\n| d | e |")
  end

  it 'keeps the spaces of a cell that fits its shrunk grid' do
    assert_equal ['a    │ b', '─────┼──────────────', 'x  y │ one two three', '     │ four'],
                 lines("| a | b |\n|---|---|\n| x  y | one two three four |", width: 20)
  end

  it 'pads a cell of wide characters by the columns they fill' do
    assert_equal ['日本 │ b', '─────┼──', 'a    │ c'], lines("| 日本 | b |\n|---|---|\n| a | c |")
  end

  it 'pads a linked cell by its visible text' do
    assert_equal "\e]8;;https://e.com\e\\\e[4m\e[38;2;77;124;255mx\e[0m\e[0m\e]8;;\e\\   \e[2m│\e[0m y",
                 lines("| key | v |\n|---|---|\n| [x](https://e.com) | y |", enabled: true).fetch(2)
  end

  it 'separates records with a blank line' do
    assert_equal ['a: 1', 'b: 2', 'c: 3', '', 'a: 4', 'b: 5', 'c: 6'],
                 lines("| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |", width: 6)
  end

  it 'lists the labels of a header with no rows when the columns cannot shrink enough' do
    assert_equal ['alpha beta', 'gamma', 'b', 'c'], lines("| alpha beta gamma | b | c |\n|---|---|---|", width: 14)
  end
end
