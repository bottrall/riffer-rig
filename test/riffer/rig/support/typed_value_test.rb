# frozen_string_literal: true

require 'test_helper'

class TypedValuePoint
  extend Riffer::Rig::Support::TypedValue::Schema
  include Riffer::Rig::Support::TypedValue

  typed_value :point, :row, :col

  attr_reader :row, :col

  def initialize(row, col)
    @row = row
    @col = col
    freeze
  end
end

class TypedValueLabel
  extend Riffer::Rig::Support::TypedValue::Schema
  include Riffer::Rig::Support::TypedValue

  typed_value 'label', :row, :col

  attr_reader :row, :col

  def initialize(row, col)
    @row = row
    @col = col
    freeze
  end
end

describe Riffer::Rig::Support::TypedValue do
  def point(row = 1, col = 2)
    TypedValuePoint.new(row, col)
  end

  describe '#type' do
    it 'returns the declared type' do
      assert_equal :point, point.type
    end

    it 'keeps a string type a string' do
      assert_equal 'label', TypedValueLabel.new(1, 2).type
    end
  end

  describe '#to_h' do
    it 'folds the type in ahead of the attributes' do
      assert_equal({ type: :point, row: 1, col: 2 }, point.to_h)
    end

    it 'keeps the declared attribute order' do
      assert_equal %i[type row col], point.to_h.keys
    end
  end

  describe 'equality' do
    it 'equals a value with the same attributes' do
      assert_equal point, point
    end

    it 'differs when an attribute differs' do
      refute_equal point, point(1, 3)
    end

    it 'differs from another class with the same attributes' do
      refute_equal point, TypedValueLabel.new(1, 2)
    end

    it 'hashes equal values alike' do
      assert_equal point.hash, point.hash
    end

    it 'is eql to a value with the same attributes' do
      assert point.eql?(point)
    end
  end
end
