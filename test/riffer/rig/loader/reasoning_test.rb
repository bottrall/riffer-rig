# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Loader::Reasoning do
  describe '.forced' do
    it 'is the flag over RIFFER_REASONING' do
      assert_equal 'high', Riffer::Rig::Loader::Reasoning.forced('high', 'low')
    end

    it 'is RIFFER_REASONING without a flag' do
      assert_equal 'low', Riffer::Rig::Loader::Reasoning.forced(nil, 'low')
    end
  end

  describe '.rejection' do
    it 'is nil without a forced level' do
      assert_nil Riffer::Rig::Loader::Reasoning.rejection(nil, nil)
    end

    it 'is nil for a level riffer accepts' do
      assert_nil Riffer::Rig::Loader::Reasoning.rejection('high', nil)
    end

    it 'refuses a flag riffer does not accept' do
      assert_match(/\Aturbo is not a reasoning level/, Riffer::Rig::Loader::Reasoning.rejection('turbo', nil))
    end

    it 'names RIFFER_REASONING when the refused level came from it' do
      assert_match(/\ARIFFER_REASONING: turbo is not/, Riffer::Rig::Loader::Reasoning.rejection(nil, 'turbo'))
    end
  end
end
