# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Columns do
  describe '.width' do
    it 'counts one column per character' do
      assert_equal 3, Riffer::Rig::Terminal::Columns.width('abc')
    end

    it 'counts a wide character as two columns' do
      assert_equal 4, Riffer::Rig::Terminal::Columns.width('日本')
    end

    it 'counts an emoji as two columns' do
      assert_equal 2, Riffer::Rig::Terminal::Columns.width('👍')
    end

    it 'counts a character forced to emoji presentation as two columns' do
      assert_equal 2, Riffer::Rig::Terminal::Columns.width("\u2764\uFE0F")
    end

    it 'counts a combining mark with its base character' do
      assert_equal 1, Riffer::Rig::Terminal::Columns.width("e\u0301")
    end

    it 'gives a lone zero-width character no columns' do
      assert_equal 0, Riffer::Rig::Terminal::Columns.width("\u200B")
    end

    it 'gives styling no columns' do
      assert_equal 2, Riffer::Rig::Terminal::Columns.width("\e[38;2;1;2;3mab\e[0m")
    end
  end

  describe '.head' do
    it 'keeps text that fits' do
      assert_equal 'abc', Riffer::Rig::Terminal::Columns.head('abc', 3)
    end

    it 'cuts text at the column limit' do
      assert_equal 'ab', Riffer::Rig::Terminal::Columns.head('abc', 2)
    end

    it 'drops a wide character that would straddle the limit' do
      assert_equal '日', Riffer::Rig::Terminal::Columns.head('日本', 3)
    end

    it 'drops everything after the cut' do
      assert_equal 'a', Riffer::Rig::Terminal::Columns.head('a日b', 2)
    end

    it 'keeps the styling around cut text' do
      assert_equal "\e[1ma\e[0m", Riffer::Rig::Terminal::Columns.head("\e[1mabc\e[0m", 1)
    end
  end

  describe '.tail' do
    it 'keeps text that fits' do
      assert_equal 'abc', Riffer::Rig::Terminal::Columns.tail('abc', 3)
    end

    it 'cuts text from the front at the column limit' do
      assert_equal 'bc', Riffer::Rig::Terminal::Columns.tail('abc', 2)
    end

    it 'drops a wide character that would straddle the limit' do
      assert_equal '本', Riffer::Rig::Terminal::Columns.tail('日本', 3)
    end
  end
end
