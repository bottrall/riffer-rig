# frozen_string_literal: true

require 'test_helper'
require 'timeout'

describe Riffer::Rig::Terminal::Wrapper do
  def wrapper(width: 10, indent: 2)
    Riffer::Rig::Terminal::Wrapper.new(width: width, indent: indent)
  end

  def verbatim(width: 10, indent: 2)
    Riffer::Rig::Terminal::Wrapper.new(width: width, indent: indent, verbatim: true)
  end

  it 'emits nothing until a line completes' do
    assert_empty wrapper << 'hello'
  end

  it 'ends a line at a CRLF as it does at a newline' do
    assert_equal "  a\n", wrapper(width: nil) << "a\r\n"
  end

  it 'emits nothing for an unterminated line when no width is known' do
    assert_empty wrapper(width: nil) << ('a' * 30)
  end

  it 'wraps a logical line as soon as it outgrows the width' do
    assert_equal "  hello\n", wrapper << 'hello world'
  end

  it 'wraps a line of wide characters as soon as it outgrows the width' do
    assert_equal "  日本語\n", wrapper << '日本語 日本'
  end

  it 'hard-splits an overfull word that has no space to break on' do
    assert_equal "  #{'a' * 8}\n", wrapper << ('a' * 12)
  end

  it 'emits no blank line for a run of spaces at the wrap boundary' do
    assert_equal "  aaaa\n  bbbb\n", wrapper(width: 7) << 'aaaa  bbbb cc'
  end

  it 'emits no line for unterminated whitespace wider than the width' do
    assert_empty wrapper << (' ' * 12)
  end

  it 'keeps a pending line as it arrived when no width is known' do
    subject = wrapper(width: nil)
    subject << 'a '

    assert_equal "  a b\n", subject << "b\n"
  end

  it 'keeps the space after the pending rest of a wrapped line' do
    subject = wrapper(width: 12)
    subject << 'hello world '

    assert_equal "  world foo\n", subject << "foo\n"
  end

  it 'emits no blank line for the whitespace trailing a line that outgrew the width' do
    subject = wrapper
    subject << "hello#{' ' * 6}"

    assert_equal "  hello\n", subject << "\n"
  end

  it 'keeps blank lines between paragraphs' do
    assert_equal "  a\n\n  b\n", wrapper << "a\n\nb\n"
  end

  it 'keeps a whitespace-only line as a blank line between paragraphs' do
    assert_equal "  a\n\n  b\n", wrapper << "a\n   \nb\n"
  end

  it 'keeps a whitespace-only line as a blank line when no width is known' do
    assert_equal "  a\n\n  b\n", wrapper(width: nil) << "a\n   \nb\n"
  end

  it 'flushes the pending line' do
    subject = wrapper
    subject << 'hello'

    assert_equal "  hello\n", subject.flush
  end

  it 'flushes nothing when only whitespace is pending' do
    subject = wrapper
    subject << '   '

    assert_empty subject.flush
  end

  it 'flushes nothing when only whitespace is pending and no width is known' do
    subject = wrapper(width: nil)
    subject << '   '

    assert_empty subject.flush
  end

  it 'forgets the pending line once it is flushed' do
    subject = wrapper
    subject << 'hello'
    subject.flush

    assert_empty subject.flush
  end

  it 'indents without wrapping when no width is known' do
    assert_equal "  #{'a' * 30}\n", wrapper(width: nil) << "#{'a' * 30}\n"
  end

  it 'hard-splits words longer than the width' do
    assert_equal "  aaaaaaaa\n  aaaa\n", wrapper << "#{'a' * 12}\n"
  end

  it 'hard-splits wide words by the columns they display in' do
    assert_equal "  日日日日\n  日日\n", wrapper << "#{'日' * 6}\n"
  end

  it 'leaves a column unused rather than splitting a wide character' do
    assert_equal "  a日日日\n  日\n", wrapper << "a日日日日\n"
  end

  it 'collapses runs of spaces between words' do
    assert_equal "  a b\n", wrapper << "a    b \n"
  end

  it 'keeps the leading whitespace of a line' do
    assert_equal "      bar(1)\n", wrapper(width: 20) << "    bar(1)\n"
  end

  it 'keeps the leading whitespace of a line that outgrows the width' do
    assert_equal "     hello\n", wrapper << '   hello world'
  end

  it 'drops leading whitespace that leaves no room for the first word' do
    assert_equal "  hello\n", wrapper << "#{' ' * 8}hello\n"
  end

  it 'drops leading whitespace that leaves no columns for a wide first word' do
    assert_equal "  日本語\n", wrapper << "    日本語\n"
  end

  it 'wraps words at the width with the indent on every line' do
    assert_equal "  hello\n  world\n  foo\n", wrapper << "hello world foo\n"
  end

  it 'starts the continuation of an indented line at the indent' do
    assert_equal "    hello\n  world\n", wrapper << "  hello world\n"
  end

  it 'hard-splits an overfull line to one column when the width equals the indent' do
    output = Timeout.timeout(1) { wrapper(width: 2) << 'ab' }

    assert_equal "  a\n", output
  end

  it 'hard-splits words to one column when the width is below the indent' do
    output = Timeout.timeout(1) { wrapper(width: 1) << "hello\n" }

    assert_equal "  h\n  e\n  l\n  l\n  o\n", output
  end

  it 'hard-splits wide words to one character a line when one column is usable' do
    output = Timeout.timeout(1) { wrapper(width: 1) << "日本\n" }

    assert_equal "  日\n  本\n", output
  end

  it 'keeps runs of spaces between words when verbatim' do
    assert_equal "  a    b\n", verbatim << "a    b\n"
  end

  it 'keeps the spaces trailing a line when verbatim' do
    assert_equal "  hello  \n", verbatim(width: 20) << "hello  \n"
  end

  it 'keeps the space at a wrap boundary when verbatim' do
    assert_equal "  hello \n  world\n", verbatim << "hello world\n"
  end

  it 'hard-splits an overfull word when verbatim' do
    assert_equal "  #{'a' * 8}\n  aaaa\n", verbatim << "#{'a' * 12}\n"
  end

  it 'hard-splits a run of spaces wider than the width when verbatim' do
    assert_equal "  a\n          \n      b\n", verbatim << "a#{' ' * 12}b\n"
  end

  it 'keeps the spaces trailing a wrapped pending line once when verbatim' do
    subject = verbatim(width: 8)
    subject << 'abcdef  '

    assert_equal "    \n", subject.flush
  end

  it 'keeps a whitespace-only line as typed when verbatim' do
    assert_equal "  a\n    \n  b\n", verbatim << "a\n  \nb\n"
  end

  it 'flushes a whitespace-only pending line as typed when verbatim' do
    subject = verbatim
    subject << '   '

    assert_equal "     \n", subject.flush
  end

  it 'emits a bare blank line for an empty line when verbatim' do
    assert_equal "  a\n\n  b\n", verbatim << "a\n\nb\n"
  end
end
