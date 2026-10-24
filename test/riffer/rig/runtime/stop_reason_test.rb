# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::StopReason do
  describe '.of' do
    it 'reads an interrupt the Runtime cancelled as cancelled' do
      outcome = Riffer::Agent::Outcome.new(reason: :interrupted, detail: 'cancelled')

      assert_equal :cancelled, Riffer::Rig::Runtime::StopReason.of(outcome)
    end

    it 'reads any other interrupt as interrupted' do
      outcome = Riffer::Agent::Outcome.new(reason: :interrupted, detail: 'blocked by a hook')

      assert_equal :interrupted, Riffer::Rig::Runtime::StopReason.of(outcome)
    end

    it 'reads any other outcome as its reason' do
      assert_equal :max_steps, Riffer::Rig::Runtime::StopReason.of(Riffer::Agent::Outcome.new(reason: :max_steps))
    end
  end
end
