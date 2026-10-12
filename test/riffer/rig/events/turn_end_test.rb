# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Events::TurnEnd do
  describe '#cost' do
    it 'is the cost of the usage' do
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5, cost: 0.0001)

      event = Riffer::Rig::Events::TurnEnd.new(:completed, usage)

      assert_in_delta(0.0001, event.cost)
    end

    it 'is nil without usage' do
      event = Riffer::Rig::Events::TurnEnd.new(:completed, nil)

      assert_nil event.cost
    end
  end
end
