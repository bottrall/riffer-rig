# frozen_string_literal: true

require 'test_helper'

class EquatableValue
  include Riffer::Rig::Support::Equatable

  attr_reader :to_h

  def initialize(to_h)
    @to_h = to_h
  end
end

class EquatableLookalike
  include Riffer::Rig::Support::Equatable

  attr_reader :to_h

  def initialize(to_h)
    @to_h = to_h
  end
end

describe Riffer::Rig::Support::Equatable do
  describe '#==' do
    it 'differs from another class with the same hash form' do
      refute_equal EquatableValue.new({ a: 1 }), EquatableLookalike.new({ a: 1 })
    end

    it 'differs from the same class with another hash form' do
      refute_equal EquatableValue.new({ a: 1 }), EquatableValue.new({ a: 2 })
    end

    it 'equals the same class with the same hash form' do
      assert_equal EquatableValue.new({ a: 1 }), EquatableValue.new({ a: 1 })
    end
  end

  describe '#hash' do
    it 'agrees for equal values' do
      assert_equal EquatableValue.new({ a: 1 }).hash, EquatableValue.new({ a: 1 }).hash
    end
  end

  describe '#eql?' do
    it 'treats equal values as the same hash key' do
      assert_equal 1, [EquatableValue.new({ a: 1 }), EquatableValue.new({ a: 1 })].uniq.size
    end
  end
end
