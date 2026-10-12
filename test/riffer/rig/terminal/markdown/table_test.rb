# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Markdown::Table do
  def lines(source, enabled: false)
    theme = Riffer::Rig::Terminal::Theme.new(enabled: enabled)
    Riffer::Rig::Terminal::Markdown::Table.lines(source.lines(chomp: true), theme: theme)
  end

  it 'returns nothing for a grid wider than the limit' do
    assert_nil lines("|#{'a' * 497}|b|\n|-|-|")
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

  it 'fills a short row with empty cells' do
    assert_equal ['a │ b', '──┼──', '1 │'], lines("| a | b |\n|---|---|\n| 1 |")
  end

  it 'widens the grid for a long row' do
    assert_equal ['a │', '──┼──', '1 │ 2'], lines("| a |\n|---|\n| 1 | 2 |")
  end

  it 'renders a header with no rows' do
    assert_equal ['a │ b', '──┼──'], lines("| a | b |\n|---|---|")
  end

  it 'pads each column to its widest cell' do
    assert_equal ['a    │ b', '─────┼──', 'long │ 2'], lines("| a | b |\n|---|---|\n| long | 2 |")
  end

  it 'measures a cell by its visible text' do
    assert_equal ["\e[1ma\e[0m \e[2m│\e[0m \e[1mb\e[0m", "\e[2m──┼──\e[0m", "\e[1mx\e[0m \e[2m│\e[0m y"],
                 lines("| a | b |\n|---|---|\n| **x** | y |", enabled: true)
  end

  it 'pads a cell with a run of spaces by its printed length' do
    assert_equal ['a  b │ c', '─────┼──', 'd    │ e'], lines("| a  b | c |\n|---|---|\n| d | e |")
  end

  it 'keeps the backticks of a code cell without colour' do
    assert_equal ['a', '───', '`x`'], lines("| a |\n|---|\n| `x` |")
  end
end
