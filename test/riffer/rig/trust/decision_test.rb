# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Trust::Decision do
  describe '#to_h' do
    it 'holds the digest and the answer' do
      assert_equal(
        { sha256: 'abc', trusted: true },
        Riffer::Rig::Trust::Decision.new(sha256: 'abc', trusted: true).to_h
      )
    end
  end
end
