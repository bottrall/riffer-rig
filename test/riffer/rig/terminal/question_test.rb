# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Question do
  def lines(question, options, width = nil, color: false)
    Riffer::Rig::Terminal::Question.lines(Riffer::Rig::Terminal::Theme.new(enabled: color), question, options, width)
  end

  describe '.lines' do
    it 'numbers the options from one' do
      assert_equal ['  1. chain', '  2. token'], lines(nil, %w[chain token])
    end

    it 'paints the option numbers when color is on' do
      assert_equal ["  \e[38;2;192;76;253m1.\e[0m chain"], lines(nil, %w[chain], color: true)
    end

    it 'leads with the question' do
      assert_equal ['Sign in with?', '  1. chain'], lines('Sign in with?', %w[chain])
    end

    it 'is the question alone without options' do
      assert_equal ['Which model?'], lines('Which model?', nil)
    end

    it 'is empty without a question or options' do
      assert_empty lines(nil, nil)
    end

    it 'leaves every line as it is without a width' do
      assert_equal ['Resume a session now', '  1. refactor the picker'],
                   lines('Resume a session now', ['refactor the picker'])
    end

    it 'leaves a question as wide as the width as it is' do
      assert_equal ['Sign in with?'], lines('Sign in with?', nil, 13)
    end

    it 'keeps the spacing of an option that fits the width' do
      assert_equal ['  1. chain  token'], lines(nil, ['chain  token'], 20)
    end

    it 'measures a painted number by the columns it shows' do
      assert_equal ["  \e[38;2;192;76;253m1.\e[0m chain"], lines(nil, %w[chain], 10, color: true)
    end

    it 'wraps an overlong question with a hanging indent' do
      assert_equal ['Resume a', '  session type', '  to filter'], lines('Resume a session type to filter', nil, 16)
    end

    it 'wraps an overlong option under its text' do
      assert_equal ['  1. refactor', '     the picker', '     now'], lines(nil, ['refactor the picker now'], 16)
    end

    it 'wraps an option under the text after a wider number' do
      options = [*Array.new(9, 'a'), 'refactor the picker']

      assert_equal ['  10. refactor', '      the picker'], lines(nil, options, 16).last(2)
    end

    it 'paints the number of an option it wraps' do
      assert_equal "  \e[38;2;192;76;253m1.\e[0m refactor", lines(nil, ['refactor the picker'], 16, color: true).first
    end
  end
end
