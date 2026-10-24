# frozen_string_literal: true

module Riffer::Rig::Terminal::Count
  extend self

  # @rbs amount: Integer
  # @rbs return: String
  def call(amount)
    return amount.to_s if amount < 1_000
    return "#{format('%g', amount.fdiv(1_000).floor(amount < 100_000 ? 1 : 0))}k" if amount < 1_000_000

    "#{format('%g', amount.fdiv(1_000_000).floor(amount < 100_000_000 ? 1 : 0))}M"
  end

  # @rbs amount: Float
  # @rbs return: String
  def cost(amount)
    format('~$%.4f', amount)
  end
end
