# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Equalizer do
  def bars(tick, color: false)
    Riffer::Rig::Terminal::Equalizer.bars(Riffer::Rig::Terminal::Theme.new(enabled: color), tick)
  end

  describe '#bars' do
    it 'draws seven bars' do
      assert_equal '▁▅██▆▂▄', bars(0)
    end

    it 'moves the bars along a column each tick' do
      assert_equal '▅██▆▂▄▇', bars(1)
    end

    it 'paints the bars cyan and magenta by turns when color is on' do
      painted = bars(0, color: true)

      assert_operator painted, :start_with?, "\e[38;2;45;226;230m▁\e[0m\e[38;2;192;76;253m▅\e[0m\e[38;2;45;226;230m█"
    end
  end
end
