# frozen_string_literal: true

module Riffer::Rig::Terminal::Equalizer
  extend self

  LEVELS = '▁▂▃▄▅▆▇█'.chars.freeze #: Array[String]

  BARS = 7 #: Integer

  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs tick: Integer
  # @rbs return: String
  def bars(theme, tick)
    Array.new(BARS) do |i|
      height = (Math.sin((tick + i) * 0.6).abs * (LEVELS.length - 1)).round
      bar = LEVELS[height]
      i.even? ? theme.cyan(bar) : theme.magenta(bar)
    end.join
  end
end
