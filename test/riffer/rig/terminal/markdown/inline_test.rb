# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Markdown::Inline do
  def parse(text, plain: false)
    Riffer::Rig::Terminal::Markdown::Inline.parse(text, plain: plain).map do |span|
      [span.text, span.styles, span.url]
    end
  end

  it 'returns no spans for empty text' do
    assert_empty parse('')
  end

  it 'returns plain text as one unstyled span' do
    assert_equal [['hello there', [], nil]], parse('hello there')
  end

  it 'leaves html as text' do
    assert_equal '<b>x</b>', parse('<b>x</b>').map(&:first).join
  end

  it 'reads a backslash escape as the literal character' do
    assert_equal '*not em*', parse('\*not em\*').map(&:first).join
  end

  it 'keeps a backslash before a letter' do
    assert_equal 'C:\dir', parse('C:\dir').map(&:first).join
  end

  it 'reads backticks as code' do
    assert_equal [['a*b*', [:code], nil]], parse('`a*b*`')
  end

  it 'lets a longer backtick run hold a backtick' do
    assert_equal [['a ` b', [:code], nil]], parse('`` a ` b ``')
  end

  it 'keeps the backticks when plain' do
    assert_equal [['`a`', [:code], nil]], parse('`a`', plain: true)
  end

  it 'leaves an unclosed backtick as text' do
    assert_equal '`open', parse('`open').map(&:first).join
  end

  it 'leaves a bare run of backticks as text' do
    assert_equal [['a ', [], nil], ['```', [], nil], [' b', [], nil]], parse('a ``` b')
  end

  it 'closes a code span only on a run as long as its opener' do
    assert_equal [['a``b', [:code], nil]], parse('`a``b`')
  end

  it 'prints a code span past the limit with its backticks' do
    assert_equal [['`', [], nil], ['a' * 1001, [], nil], ['`', [], nil]], parse("`#{'a' * 1001}`")
  end

  it 'reads triple asterisks as bold italic' do
    assert_equal [['b', %i[bold italic], nil]], parse('***b***')
  end

  it 'prints a bold italic span past the limit with its markers' do
    assert_equal "***#{'a' * 1001}***", parse("***#{'a' * 1001}***").map(&:first).join
  end

  it 'reads double asterisks as bold' do
    assert_equal [['a ', [], nil], ['b', [:bold], nil]], parse('a **b**')
  end

  it 'reads double underscores as bold' do
    assert_equal [['b', [:bold], nil]], parse('__b__')
  end

  it 'nests italic inside bold' do
    assert_equal [['a ', [:bold], nil], ['b', %i[bold italic], nil]], parse('**a *b***')
  end

  it 'leaves unclosed emphasis as text' do
    assert_equal '**open', parse('**open').map(&:first).join
  end

  it 'prints a strong span past the limit with its markers' do
    assert_equal "**#{'a' * 1001}**", parse("**#{'a' * 1001}**").map(&:first).join
  end

  it 'reads single asterisks as italic' do
    assert_equal [['b', [:italic], nil]], parse('*b*')
  end

  it 'reads single underscores as italic' do
    assert_equal [['b', [:italic], nil]], parse('_b_')
  end

  it 'leaves underscores inside a word alone' do
    assert_equal 'snake_case_name', parse('snake_case_name').map(&:first).join
  end

  it 'styles nothing in a word with underscores' do
    assert_equal [[]], parse('snake_case_name').map { |span| span[1] }.uniq
  end

  it 'leaves spaced asterisks alone' do
    assert_equal '2 * 3 * 4', parse('2 * 3 * 4').map(&:first).join
  end

  it 'styles an emphasis span as long as the limit' do
    assert_equal [['a' * 1000, [:italic], nil]], parse("*#{'a' * 1000}*")
  end

  it 'prints an emphasis span past the limit with its markers' do
    assert_equal "*#{'a' * 1001}*", parse("*#{'a' * 1001}*").map(&:first).join
  end

  it 'reads a link without a title' do
    assert_equal [['docs', [], 'https://example.com']], parse('[docs](https://example.com)')
  end

  it 'drops a link title' do
    assert_equal [['docs', [], 'https://example.com']], parse('[docs](https://example.com "Title")')
  end

  it 'keeps balanced parentheses in a link target' do
    assert_equal [['w', [], 'https://e.org/Foo_(bar)']], parse('[w](https://e.org/Foo_(bar))')
  end

  it 'styles the label of a link' do
    assert_equal [['b', [:bold], 'https://example.com']], parse('[**b**](https://example.com)')
  end

  it 'reads an image as a link to its source' do
    assert_equal [['alt', [], 'https://example.com/a.png']], parse('![alt](https://example.com/a.png)')
  end

  it 'reads a mailto target as a hyperlink' do
    assert_equal [['mail', [], 'mailto:a@example.com']], parse('[mail](mailto:a@example.com)')
  end

  it 'links a label as long as the limit' do
    assert_equal [['a' * 1000, [], 'https://e.com']], parse("[#{'a' * 1000}](https://e.com)")
  end

  it 'prints a link whose label is past the limit as written' do
    assert_equal "[#{'a' * 1001}](https://e.com)", parse("[#{'a' * 1001}](https://e.com)").map(&:first).join
  end

  it 'leaves a reference-style link as text' do
    assert_equal '[ref][1]', parse('[ref][1]').map(&:first).join
  end

  it 'does not repeat a target that is its own label' do
    assert_equal 'https://e.com', parse('[https://e.com](https://e.com)', plain: true).map(&:first).join
  end

  it 'spells the target out when plain' do
    assert_equal [['docs', [], nil], [' (https://e.com)', [], nil]], parse('[docs](https://e.com)', plain: true)
  end

  it 'spells out a relative target instead of linking it' do
    assert_equal [['guide', [], nil], [' (docs/HOSTS.md)', [], nil]], parse('[guide](docs/HOSTS.md)')
  end

  it 'spells out a target with an unsafe scheme instead of linking it' do
    assert_equal [['x', [], nil], [' (javascript:alert(1))', [], nil]], parse('[x](javascript:alert(1))')
  end

  it 'spells out a target with a non-ascii character instead of linking it' do
    assert_equal [['x', [], nil], [' (https://exämple.com)', [], nil]], parse('[x](https://exämple.com)')
  end
end
