# frozen_string_literal: true

module Riffer::Rig::Terminal::Spinner
  extend self

  FRAMES = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze #: Array[String]

  # @rbs tick: Integer
  # @rbs return: String
  def call(tick)
    FRAMES[tick % FRAMES.length]
  end
end
