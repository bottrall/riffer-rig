# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require_relative '../../../support/display_runtime'

describe Riffer::Rig::Terminal::QuietDisplay do
  before do
    @io = StringIO.new
    @runtime = DisplayRuntime.new
  end

  def display
    @display ||= Riffer::Rig::Terminal::QuietDisplay.new(
      io: @io,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: false),
      clock: -> { 0.0 }
    )
  end

  def terminal(&)
    @io = StringIO.new
    @io.define_singleton_method(:tty?) { true }
    @io.define_singleton_method(:winsize, &)
  end

  def show(*events, runtime: @runtime)
    display.start(runtime)
    events.each { |event| display.absorb(event) }
    display.finish(runtime)
  end

  def text(content)
    Riffer::StreamEvents::TextDelta.new(content)
  end

  def turn_end
    Riffer::Rig::Events::TurnEnd.new(:completed, nil)
  end

  describe '#start' do
    it 'leaves the turn before out of the next one' do
      show(text('First.'), turn_end)
      @io.truncate(0)

      show(turn_end)

      refute_includes @io.string, 'First.'
    end
  end

  describe '#absorb' do
    it 'prints nothing while the turn runs' do
      display.start(@runtime)

      display.absorb(text('All done.'))

      assert_empty @io.string
    end
  end

  describe '#cancel' do
    it 'cancels the Runtime' do
      display.cancel(@runtime)

      assert_equal 1, @runtime.cancels
    end
  end

  describe '#finish' do
    it 'prints nothing for a turn that has not ended' do
      show(text('Half a sen'))

      assert_empty @io.string
    end

    it 'wraps the report to the width of a terminal' do
      terminal { [24, 12] }

      show(text('one two three four five'), turn_end)

      assert_includes @io.string, "  one two\n  three four\n  five\n"
    end

    it 'prints the answer and the stat footer of a turn that has ended' do
      show(text('All done.'), turn_end)

      assert_equal "\n  All done.\n\n  1 step · 00:00\n", @io.string
    end

    it 'reports the session total of the Runtime' do
      tally = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)

      show(turn_end, runtime: DisplayRuntime.new(tally: tally))

      assert_includes @io.string, 'session 15 tok'
    end
  end
end
