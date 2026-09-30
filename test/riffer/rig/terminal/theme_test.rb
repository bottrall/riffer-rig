# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Terminal::Theme do
  it 'paints text with an ansi escape when enabled' do
    theme = Riffer::Rig::Terminal::Theme.new(enabled: true)

    assert_includes theme.pink('hi'), "\e[38;2;"
  end

  it 'returns raw text when disabled' do
    theme = Riffer::Rig::Terminal::Theme.new(enabled: false)

    assert_equal 'hi', theme.pink('hi')
  end

  it 'dim is a passthrough when disabled' do
    theme = Riffer::Rig::Terminal::Theme.new(enabled: false)

    assert_equal 'hi', theme.dim('hi')
  end

  it 'purple is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::Terminal::Theme.new(enabled: false).purple('hi')
  end

  it 'blue is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::Terminal::Theme.new(enabled: false).blue('hi')
  end

  it 'red is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::Terminal::Theme.new(enabled: false).red('hi')
  end

  it 'bold is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::Terminal::Theme.new(enabled: false).bold('hi')
  end

  it 'for disables colour for a non tty' do
    refute Riffer::Rig::Terminal::Theme.for(StringIO.new).enabled
  end

  it 'for enables colour for a tty' do
    assert Riffer::Rig::Terminal::Theme.for(tty).enabled
  end

  it 'for disables colour when asked for no colour' do
    refute Riffer::Rig::Terminal::Theme.for(tty, no_color: true).enabled
  end

  private

  def tty
    StringIO.new.tap { |io| io.define_singleton_method(:tty?) { true } }
  end
end
