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

    it 'shows the control characters of a prompt as pictures' do
      assert_equal '› Go␛[2J␊now', echo("Go\e[2J\nnow")
    end

    it 'wraps the prompt at a word with a hanging indent under its text' do
      assert_equal "› refactor the\n  picker now", echo('refactor the picker now', width: 16)
    end

    it 'keeps a long prompt on one line without a width' do
      assert_equal '› refactor the picker now', echo('refactor the picker now')
    end

    it 'keeps the prompt glyph on a prompt of only spaces' do
      assert_equal '› ', echo('   ', width: 16)
    end

    it 'paints the prompt glyph pink' do
      assert_equal "\e[38;2;255;106;193m›\e[0m Go", echo('Go', color: true)
    end
  end
end
