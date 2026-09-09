# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::UI::Cursor do
  def setup
    @io = StringIO.new
    @cursor = Riffer::Rig::UI::Cursor.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: false))
  end

  it 'hide is a no op when not a tty' do
    @cursor.hide

    assert_equal '', @io.string
  end

  it 'show is a no op when not a tty' do
    @cursor.show

    assert_equal '', @io.string
  end

  it 'hide prints the hide sequence when enabled' do
    @cursor = Riffer::Rig::UI::Cursor.new(io: tty_io, theme: Riffer::Rig::UI::Theme.new(enabled: true))

    @cursor.hide

    assert_equal "\e[?25l", @io.string
  end

  it 'show prints the show sequence when enabled' do
    @cursor = Riffer::Rig::UI::Cursor.new(io: tty_io, theme: Riffer::Rig::UI::Theme.new(enabled: true))

    @cursor.show

    assert_equal "\e[?25h", @io.string
  end

  private

  def tty_io
    @io = StringIO.new
    @io.define_singleton_method(:tty?) { true }
    @io
  end
end
