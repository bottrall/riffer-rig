# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::UI::Theme do
  it 'paints text with an ansi escape when enabled' do
    theme = Riffer::Rig::UI::Theme.new(enabled: true)

    assert_includes theme.pink('hi'), "\e[38;2;"
  end

  it 'returns raw text when disabled' do
    theme = Riffer::Rig::UI::Theme.new(enabled: false)

    assert_equal 'hi', theme.pink('hi')
  end

  it 'dim is a passthrough when disabled' do
    theme = Riffer::Rig::UI::Theme.new(enabled: false)

    assert_equal 'hi', theme.dim('hi')
  end

  it 'purple is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::UI::Theme.new(enabled: false).purple('hi')
  end

  it 'blue is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::UI::Theme.new(enabled: false).blue('hi')
  end

  it 'red is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::UI::Theme.new(enabled: false).red('hi')
  end

  it 'bold is a passthrough when disabled' do
    assert_equal 'hi', Riffer::Rig::UI::Theme.new(enabled: false).bold('hi')
  end

  it 'for disables colour for a non tty' do
    refute Riffer::Rig::UI::Theme.for(StringIO.new).enabled
  end

  it 'for enables colour for a tty the env says nothing about' do
    assert Riffer::Rig::UI::Theme.for(tty, env: Riffer::Rig::Env.new({})).enabled
  end

  it 'for disables colour when the injected env sets NO_COLOR' do
    refute Riffer::Rig::UI::Theme.for(tty, env: Riffer::Rig::Env.new('NO_COLOR' => '1')).enabled
  end

  private

  def tty
    StringIO.new.tap { |io| io.define_singleton_method(:tty?) { true } }
  end
end
