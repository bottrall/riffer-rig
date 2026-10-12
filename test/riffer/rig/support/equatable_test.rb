# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Support::Equatable do
  def build_class
    Class.new do
      include Riffer::Rig::Support::Equatable

      def initialize(attrs)
        @attrs = attrs
      end

      def to_h
        @attrs
      end
    end
  end

  let(:point_class) { build_class }
  let(:other_class) { build_class }

  def point(attrs = { row: 1, col: 2 }, klass: point_class)
    klass.new(attrs)
  end

  describe '#==' do
    it 'equals a value of the same class with the same attributes' do
      assert_equal point, point({ row: 1, col: 2 })
    end

    it 'differs from a value of the same class with different attributes' do
      refute_equal point, point({ row: 1, col: 3 })
    end

    it 'differs from a value of another class with the same attributes' do
      refute_equal point, point({ row: 1, col: 2 }, klass: other_class)
    end

    it 'differs from nil' do
      refute_equal point, nil
    end
  end

  describe '#hash' do
    it 'hashes equal values alike' do
      assert_equal point.hash, point({ row: 1, col: 2 }).hash
    end

    it 'hashes a value of another class with the same attributes differently' do
      refute_equal point.hash, point({ row: 1, col: 2 }, klass: other_class).hash
    end
  end

  describe '#eql?' do
    it 'is eql to a value of the same class with the same attributes' do
      assert point.eql?(point({ row: 1, col: 2 }))
    end

    it 'is not eql to a value with different attributes' do
      refute point.eql?(point({ row: 1, col: 3 }))
    end

    it 'collapses equal values to a single Hash key' do
      assert_equal 1, { point => :first, point({ row: 1, col: 2 }) => :second }.size
    end
  end
end
