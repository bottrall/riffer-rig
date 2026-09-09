# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class Riffer::Rig::UI::MarkdownPainterTest < Minitest::Test
  def setup
    @io = StringIO.new
    @theme = Riffer::Rig::UI::Theme.new(enabled: false)
    @painter = Riffer::Rig::UI::MarkdownPainter.new(io: @io, theme: @theme)
  end

  def test_finish_prints_a_rendered_block_off_tty
    @painter << 'Hello **bold** world'
    @painter.finish

    assert_includes @io.string, 'Hello bold world'
  end

  def test_off_tty_output_has_no_escape_sequences
    @painter << 'plain'
    @painter.finish

    refute_includes @io.string, "\e"
  end

  def test_off_tty_deliveries_accumulate_into_one_render
    @painter << 'one '
    @painter << 'two'
    @painter.finish

    assert_equal "one two\n", @io.string
  end

  def test_tty_delivery_repaints_with_erase_and_row_codes
    painter = tty_painter
    painter << 'Hello world'

    assert_includes @io.string, "\e[2KHello world\r\n"
  end

  def test_tty_render_identical_lines_skip_the_repaint
    painter = tty_painter
    painter << 'Hello world'
    @io.reopen(StringIO.new)

    painter << "\n"

    assert_equal '', @io.string
  end

  def test_finish_resets_row_tracking
    painter = tty_painter
    painter << 'Hello world'
    painter.finish
    @io.reopen(StringIO.new)

    painter << 'next'
    painter << 'next'

    assert_includes @io.string, 'next'
  end

  private

  def tty_painter
    @io.define_singleton_method(:tty?) { true }
    @io.define_singleton_method(:winsize) { [24, 80] }
    @theme = Riffer::Rig::UI::Theme.new(enabled: true)
    Riffer::Rig::UI::MarkdownPainter.new(io: @io, theme: @theme)
  end
end
