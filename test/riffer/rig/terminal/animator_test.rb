# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::Terminal::Animator do
  def setup
    @io = StringIO.new
    @animator = Riffer::Rig::Terminal::Animator.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
  end

  def tty_io
    StringIO.new.tap { |io| io.define_singleton_method(:tty?) { true } }
  end

  it 'reveal prints the final frame when not a tty' do
    @animator.reveal([['frame one'], ['final']])

    assert_equal "final\n", @io.string
  end

  it 'reveal prints only the final frame when the theme is disabled on a tty' do
    io = tty_io
    animator = Riffer::Rig::Terminal::Animator.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
    animator.reveal([['frame one'], ['final']])

    assert_equal "final\n", io.string
  end

  it 'reveal prints only the final frame when the theme is enabled off a tty' do
    animator = Riffer::Rig::Terminal::Animator.new(io: @io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.reveal([['frame one'], ['final']])

    assert_equal "final\n", @io.string
  end

  it 'reveal redraws each frame over the last and leaves the final one in place' do
    io = tty_io
    animator = Riffer::Rig::Terminal::Animator.new(io: io, theme: Riffer::Rig::Terminal::Theme.new(enabled: true))
    animator.reveal([%w[a b], %w[c d]])

    assert_equal "a\e[K\nb\e[K\n\e[2A\rc\e[K\nd\e[K\n", io.string
  end
end
