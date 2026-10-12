# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Markdown::Blocks do
  def split(source)
    Riffer::Rig::Terminal::Markdown::Blocks.split(source.lines(chomp: true))
  end

  def kind(source)
    Riffer::Rig::Terminal::Markdown::Blocks.kind(source.lines(chomp: true), 0)
  end

  describe '.split' do
    it 'returns no blocks for no lines' do
      assert_empty Riffer::Rig::Terminal::Markdown::Blocks.split([])
    end

    it 'keeps the lines of a paragraph together' do
      assert_equal [%w[a b]], split("a\nb")
    end

    it 'gives a run of blank lines a block of its own' do
      assert_equal [['a'], ['', ''], ['b']], split("a\n\n\nb")
    end

    it 'ends a paragraph at a heading' do
      assert_equal [['a'], ['# b'], ['c']], split("a\n# b\nc")
    end

    it 'ends a paragraph at a list' do
      assert_equal [['a'], ['- b']], split("a\n- b")
    end

    it 'takes a fence through its closing line' do
      assert_equal [['```', 'a', '', '# b', '```'], ['c']], split("```\na\n\n# b\n```\nc")
    end

    it 'takes an unclosed fence to the end' do
      assert_equal [['```', 'a', '', 'b']], split("```\na\n\nb")
    end

    it 'does not close a fence on a shorter one' do
      assert_equal [['````', '```', '````']], split("````\n```\n````")
    end

    it 'does not close a backtick fence on a tilde fence' do
      assert_equal [['```', '~~~', '```']], split("```\n~~~\n```")
    end

    it 'keeps indented and blank lines with their list' do
      assert_equal [['- a', '', '  b', '- c'], ['d']], split("- a\n\n  b\n- c\nd")
    end

    it 'keeps the lines of a quote together' do
      assert_equal [['> a', '> b'], ['c']], split("> a\n> b\nc")
    end

    it 'takes a table through its last row' do
      assert_equal [['| a |', '|---|', '| b |'], ['c']], split("| a |\n|---|\n| b |\nc")
    end
  end

  describe '.kind' do
    it 'classifies a blank line' do
      assert_equal :blank, kind('  ')
    end

    it 'classifies a backtick fence' do
      assert_equal :fence, kind('```ruby')
    end

    it 'classifies a tilde fence' do
      assert_equal :fence, kind('~~~')
    end

    it 'does not classify inline code spanning a line as a fence' do
      assert_equal :paragraph, kind('```a``` b')
    end

    it 'classifies a heading' do
      assert_equal :heading, kind('### a')
    end

    it 'does not classify seven marks as a heading' do
      assert_equal :paragraph, kind('####### a')
    end

    it 'classifies a rule' do
      assert_equal :rule, kind('* * *')
    end

    it 'classifies a quote' do
      assert_equal :quote, kind('> a')
    end

    it 'classifies an unordered item' do
      assert_equal :list, kind('+ a')
    end

    it 'classifies an ordered item' do
      assert_equal :list, kind('12) a')
    end

    it 'does not classify emphasis at the start of a line as a list' do
      assert_equal :paragraph, kind('*a* b')
    end

    it 'classifies a row followed by a divider as a table' do
      assert_equal :table, kind("a | b\n--- | ---")
    end

    it 'does not classify a row without a divider as a table' do
      assert_equal :paragraph, kind("a | b\nc | d")
    end

    it 'classifies anything else as a paragraph' do
      assert_equal :paragraph, kind('<div>')
    end
  end

  describe '.closing' do
    it 'matches a fence at least as long as the opening one' do
      assert_match Riffer::Rig::Terminal::Markdown::Blocks.closing('```'), '````'
    end

    it 'does not match a fence followed by text' do
      refute_match Riffer::Rig::Terminal::Markdown::Blocks.closing('```'), '```ruby'
    end

    it 'matches a fence longer than a regexp repeat count allows' do
      assert_match Riffer::Rig::Terminal::Markdown::Blocks.closing('~' * 100_001), '~' * 100_001
    end
  end
end
