# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Tally do
  it 'shows the token total alone when the usage is unpriced' do
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 300, output_tokens: 150)

    assert_equal '450 tok', Riffer::Rig::Terminal::Tally.call(usage)
  end

  it 'appends the cost when the usage is priced' do
    usage = Riffer::Providers::TokenUsage.new(input_tokens: 300, output_tokens: 150, cost: 0.25)

    assert_equal '450 tok · ~$0.2500', Riffer::Rig::Terminal::Tally.call(usage)
  end
end
