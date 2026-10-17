# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Echo do
  def echo(prompt, color: false, width: nil)
    Riffer::Rig::Terminal::Echo.call(prompt, theme: Riffer::Rig::Terminal::Theme.new(enabled: color), width: width)
  end

  describe '.call' do
    it 'shows the prompt after the prompt glyph' do
      assert_equal '› hello', echo('hello')
    end

    it 'shows a tab in the prompt as spaces' do
      assert_equal '›     at Foo', echo("\tat Foo")
    end

    it 'shows each line of the prompt on a row of its own under the hanging indent' do
      assert_equal "› one\n  two", echo("one\ntwo")
    end

    it 'breaks the prompt at a carriage return and line feed' do
      assert_equal "› one\n  two", echo("one\r\ntwo")
    end

    it 'shows the other control characters of a prompt as pictures' do
      assert_equal '› Go␛[2J now', echo("Go\e[2J now")
    end

    it 'keeps the indentation of a line of the prompt' do
      assert_equal "› trace\n    at Foo", echo("trace\n  at Foo")
    end

    it 'keeps a blank line inside the prompt' do
      assert_equal "› one\n\n  two", echo("one\n\ntwo")
    end

    it 'wraps the prompt at a word with a hanging indent under its text' do
      assert_equal "› refactor the\n  picker now", echo('refactor the picker now', width: 16)
    end

    it 'keeps a long prompt on one line without a width' do
      assert_equal '› refactor the picker now', echo('refactor the picker now')
    end

    it 'drops the blank lines around the prompt' do
      assert_equal '› one', echo("\n  \none\n\n")
    end

    it 'keeps the prompt glyph on a prompt of only spaces' do
      assert_equal '› ', echo('   ', width: 16)
    end

    it 'paints the prompt glyph pink' do
      assert_equal "\e[38;2;255;106;193m›\e[0m Go", echo('Go', color: true)
    end
  end
end
