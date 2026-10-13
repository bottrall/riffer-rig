# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Question do
  def lines(question, options, color: false)
    Riffer::Rig::Terminal::Question.lines(Riffer::Rig::Terminal::Theme.new(enabled: color), question, options)
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
  end
end
