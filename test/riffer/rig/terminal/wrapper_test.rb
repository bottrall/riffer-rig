# frozen_string_literal: true

require 'test_helper'
require 'timeout'

describe Riffer::Rig::Terminal::Wrapper do
  def wrapper(width: 10, indent: 2)
    Riffer::Rig::Terminal::Wrapper.new(width: width, indent: indent)
  end

  it 'emits nothing until a line completes' do
    assert_empty wrapper << 'hello'
  end

  it 'emits nothing for an unterminated line when no width is known' do
    assert_empty wrapper(width: nil) << ('a' * 30)
  end

  it 'wraps a logical line as soon as it outgrows the width' do
    assert_equal "  hello\n", wrapper << 'hello world'
  end

  it 'hard-splits an overfull word that has no space to break on' do
    assert_equal "  #{'a' * 8}\n", wrapper << ('a' * 12)
  end

  it 'hard-splits an overfull line to one column when the width equals the indent' do
    output = Timeout.timeout(1) { wrapper(width: 2) << 'ab' }

    assert_equal "  a\n", output
  end

  it 'keeps blank lines between paragraphs' do
    assert_equal "  a\n\n  b\n", wrapper << "a\n\nb\n"
  end

  it 'indents without wrapping when no width is known' do
    assert_equal "  #{'a' * 30}\n", wrapper(width: nil) << "#{'a' * 30}\n"
  end

  it 'wraps words at the width with the indent on every line' do
    assert_equal "  hello\n  world\n  foo\n", wrapper << "hello world foo\n"
  end

  it 'collapses runs of spaces' do
    assert_equal "  a b\n", wrapper << "  a    b \n"
  end

  it 'hard-splits words longer than the width' do
    assert_equal "  aaaaaaaa\n  aaaa\n", wrapper << "#{'a' * 12}\n"
  end

  it 'hard-splits words to one column when the width is below the indent' do
    output = Timeout.timeout(1) { wrapper(width: 1) << "hello\n" }

    assert_equal "  h\n  e\n  l\n  l\n  o\n", output
  end

  it 'emits no line for the leading whitespace of an overfull line' do
    assert_equal "  hello\n", wrapper << '   hello world'
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
end
