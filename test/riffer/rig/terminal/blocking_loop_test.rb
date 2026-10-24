# frozen_string_literal: true

require 'test_helper'
require 'stringio'

class ScriptedInput
  def initialize(steps)
    @steps = steps.dup
  end

  def gets
    step = @steps.shift
    raise Interrupt if step == :interrupt

    step
  end
end

describe Riffer::Rig::Terminal::BlockingLoop do
  def blocking_loop(*steps)
    @output = StringIO.new
    renderer = Riffer::Rig::Terminal::Renderer.new(io: @output, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
    Riffer::Rig::Terminal::BlockingLoop.new(input: ScriptedInput.new(steps), renderer: renderer)
  end

  def yielded(*steps, &turn)
    seen = []
    blocking_loop(*steps).run do |entry|
      seen << entry
      turn&.call(entry)
    end
    seen
  end

  def hints = @output.string.scan(Riffer::Rig::Terminal::EXIT_HINT).length

  describe '#run' do
    it 'prompts before each line' do
      yielded("one\n", nil)

      assert_equal 2, @output.string.scan('› ').length
    end

    it 'ends at the end of the input' do
      assert_empty yielded(nil, "one\n")
    end

    it 'yields each line stripped of the whitespace around it' do
      assert_equal ['/model  opus'], yielded("  /model  opus \n", nil)
    end

    it 'skips a blank line' do
      assert_equal ['one'], yielded("  \n", "one\n", nil)
    end

    it 'hints at the second Ctrl-C after the first at the prompt' do
      yielded(:interrupt, nil)

      assert_equal 1, hints
    end

    it 'ends on a second Ctrl-C at the prompt' do
      assert_empty yielded(:interrupt, :interrupt, "one\n")
    end

    it 'disarms the exit on a line between two Ctrl-Cs' do
      yielded(:interrupt, "\n", :interrupt, nil)

      assert_equal 2, hints
    end

    it 'arms the exit when a Ctrl-C escapes a turn' do
      yielded("one\n", nil) { raise Interrupt }

      assert_equal 1, hints
    end

    it 'carries on after a Ctrl-C escapes a turn' do
      assert_equal %w[one two], yielded("one\n", "two\n", nil) { |entry| raise Interrupt if entry == 'one' }
    end
  end

  describe '#arm' do
    it 'arms the exit' do
      assert blocking_loop.arm
    end

    it 'shows the exit hint' do
      blocking_loop.arm

      assert_equal 1, hints
    end

    it 'reports an exit already armed' do
      armed = blocking_loop
      armed.arm

      refute armed.arm
    end
  end
end
