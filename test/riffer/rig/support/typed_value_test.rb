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

describe Riffer::Rig::Support::TypedValue do
  def point(row = 1, col = 2)
    TypedValuePoint.new(row, col)
  end

  describe '#type' do
    it 'returns the declared type' do
      assert_equal :point, point.type
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
end
