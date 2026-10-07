# frozen_string_literal: true

module Riffer::Rig::Terminal::Format
  extend self

  # @rbs seconds: Float
  # @rbs return: String
  def elapsed(seconds)
    return "#{seconds.round}s" if seconds < 60.0

    "#{seconds.div(60)}m#{format('%02d', seconds.round % 60)}s"
  end

  # @rbs count: Integer
  # @rbs return: String
  def tokens(count)
    return count.to_s if count < 1000

    "#{format('%.1f', count / 1000.0)}k"
  end
end
