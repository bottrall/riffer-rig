# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::IdleBar do
  def now = Time.new(2026, 1, 1, 14, 32)

  def usage(input: 132_000, output: 218_000, cost: 1.4)
    Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output, cost: cost)
  end

  it 'joins the model, the odometer, the cost and the clock' do
    assert_equal 'sonnet-4-6 · ↑132k ↓218k tok · ~$1.4000 · 14:32',
                 Riffer::Rig::Terminal::IdleBar.call(model: 'sonnet-4-6', tally: usage, now: now)
  end

  it 'leaves the odometer and the cost out before the session has used tokens' do
    assert_equal 'sonnet-4-6 · 14:32', Riffer::Rig::Terminal::IdleBar.call(model: 'sonnet-4-6', tally: nil, now: now)
  end

  it 'leaves the cost out while the model is unpriced' do
    assert_equal 'sonnet-4-6 · ↑132k ↓218k tok · 14:32',
                 Riffer::Rig::Terminal::IdleBar.call(model: 'sonnet-4-6', tally: usage(cost: nil), now: now)
  end
end
