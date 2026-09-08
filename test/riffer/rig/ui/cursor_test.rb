# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class Riffer::Rig::UI::CursorTest < Minitest::Test
  def setup
    @io = StringIO.new
    @cursor = Riffer::Rig::UI::Cursor.new(io: @io, theme: Riffer::Rig::UI::Theme.new(enabled: false))
  end

  def test_hide_is_a_no_op_when_not_a_tty
    @cursor.hide

    assert_equal '', @io.string
  end

  def test_show_is_a_no_op_when_not_a_tty
    @cursor.show

    assert_equal '', @io.string
  end

  def test_hide_prints_the_hide_sequence_when_enabled
    @cursor = Riffer::Rig::UI::Cursor.new(io: tty_io, theme: Riffer::Rig::UI::Theme.new(enabled: true))

    @cursor.hide

    assert_equal "\e[?25l", @io.string
  end

  def test_show_prints_the_show_sequence_when_enabled
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
