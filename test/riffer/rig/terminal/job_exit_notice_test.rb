# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::JobExitNotice do
  describe '.call' do
    it 'tells of a single exit' do
      assert_equal '1 background job exited', Riffer::Rig::Terminal::JobExitNotice.call(1)
    end

    it 'tells of several exits' do
      assert_equal '2 background jobs exited', Riffer::Rig::Terminal::JobExitNotice.call(2)
    end
  end
end
