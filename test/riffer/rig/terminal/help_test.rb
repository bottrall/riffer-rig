# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Help do
  def entry(name, about = 'About')
    Riffer::Rig::Terminal::Builtin.new(name, description: about)
  end

  describe '.call' do
    def help(commands)
      Riffer::Rig::Terminal::Help.call(commands.map { |name, about| entry(name, about) })
    end

    it 'lists the commands in the order of their names, descriptions aligned' do
      rows = help('resume' => 'Resume', 'auth' => 'Auth', 'new' => 'New').lines(chomp: true).first(3)

      assert_equal ['/auth    Auth', '/new     New', '/resume  Resume'], rows
    end

    it 'ends with a pointer to the palette and the keys' do
      assert_equal "\n#{Riffer::Rig::Terminal::Help::POINTER}", help('new' => 'New').lines.drop(1).join
    end
  end

  describe '.width' do
    it 'measures the widest name by display width' do
      assert_equal 4, Riffer::Rig::Terminal::Help.width([entry('曲曲'), entry('abc')])
    end
  end

  describe '.label' do
    it 'pads the name to the width by display width' do
      assert_equal '/曲 ', Riffer::Rig::Terminal::Help.label(entry('曲'), 3)
    end
  end

  describe '.about' do
    it 'keeps a description with a line break on one row' do
      assert_equal 'Start fresh', Riffer::Rig::Terminal::Help.about(entry('new', "Start\nfresh\n"))
    end
  end
end
