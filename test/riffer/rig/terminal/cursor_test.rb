# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Terminal::Cursor do
  def setup
    @io = StringIO.new
    @cursor = Riffer::Rig::Terminal::Cursor.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
  end

  it 'hide is a no op when not a tty' do
    @cursor.hide

    assert_equal '', @io.string
  end

  it 'show is a no op when not a tty' do
    @cursor.show

    assert_equal '', @io.string
  end

  it 'hide is a no op when the theme is disabled on a tty' do
    @cursor = Riffer::Rig::Terminal::Cursor.new(io: tty_io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))

    @cursor.hide

    assert_equal '', @io.string
  end

  it 'hide is a no op when the theme is enabled but the io is not a tty' do
    @io = StringIO.new
    @cursor = Riffer::Rig::Terminal::Cursor.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))

    @cursor.hide

    assert_equal '', @io.string
  end

  it 'show then hide print their sequences when enabled' do
    @cursor = Riffer::Rig::Terminal::Cursor.new(io: tty_io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))

    @cursor.show
    @cursor.hide

    assert_equal "\e[?25h\e[?25l", @io.string
  end

  private

  def tty_io
    @io = StringIO.new
    @io.define_singleton_method(:tty?) { true }
    @io
  end
end
