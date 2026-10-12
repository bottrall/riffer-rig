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

  it 'italic is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::Terminal::Theme.new(enabled: false).italic('hi')
  end

  it 'italic wraps text in the italic escape when enabled' do
    assert_equal "\e[3mhi\e[0m", Riffer::Rig::Terminal::Theme.new(enabled: true).italic('hi')
  end

  it 'underline is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::Terminal::Theme.new(enabled: false).underline('hi')
  end

  it 'underline wraps text in the underline escape when enabled' do
    assert_equal "\e[4mhi\e[0m", Riffer::Rig::Terminal::Theme.new(enabled: true).underline('hi')
  end

  it 'heading is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::Terminal::Theme.new(enabled: false).heading('hi')
  end

  it 'heading is bold purple when enabled' do
    assert_equal "\e[1m\e[38;2;122;92;255mhi\e[0m\e[0m", Riffer::Rig::Terminal::Theme.new(enabled: true).heading('hi')
  end

  it 'code is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::Terminal::Theme.new(enabled: false).code('hi')
  end

  it 'code is cyan when enabled' do
    assert_equal "\e[38;2;45;226;230mhi\e[0m", Riffer::Rig::Terminal::Theme.new(enabled: true).code('hi')
  end

  it 'link is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::Terminal::Theme.new(enabled: false).link('hi', 'https://example.com')
  end

  it 'link is an underlined blue osc 8 hyperlink when enabled' do
    assert_equal(
      "\e]8;;https://example.com\e\\\e[4m\e[38;2;77;124;255mhi\e[0m\e[0m\e]8;;\e\\",
      Riffer::Rig::Terminal::Theme.new(enabled: true).link('hi', 'https://example.com')
    )
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
