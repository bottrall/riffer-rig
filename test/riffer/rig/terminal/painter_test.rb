# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Terminal::Painter do
  def paint(line, owners, same: ->(left, right) { left == right })
    Riffer::Rig::Terminal::Painter.new(same: same).paint(line, owners) { |text, owner| "<#{owner}>#{text}</#{owner}>" }
  end

  it 'is frozen' do
    assert_predicate Riffer::Rig::Terminal::Painter.new(same: ->(left, right) { left == right }), :frozen?
  end

  describe '#paint' do
    it 'paints nothing for an empty line' do
      assert_equal '', paint('', [])
    end

    it 'hands each visible character to its owner' do
      assert_equal '<a>x</a><b>y</b>', paint('xy', %i[a b])
    end

    it 'joins neighbouring characters of one owner into one run' do
      assert_equal '<a>xy</a>', paint('xy', %i[a a])
    end

    it 'gives whitespace between two characters of one owner to that owner' do
      assert_equal '<a>x  y</a>', paint('x  y', %i[a a])
    end

    it 'leaves whitespace between two owners unowned' do
      assert_equal '<a>x</a><> </><b>y</b>', paint('x y', %i[a b])
    end

    it 'joins neighbouring unowned characters into one run' do
      assert_equal '<a>x</a><>  </><b>y</b>', paint('x  y', %i[a b])
    end

    it 'leaves leading whitespace unowned' do
      assert_equal '<> </><a>x</a>', paint(' x', %i[a])
    end

    it 'leaves trailing whitespace unowned' do
      assert_equal '<a>x</a><> </>', paint('x ', %i[a])
    end

    it 'leaves a visible character past the last owner unowned' do
      assert_equal '<a>x</a><>y</>', paint('xy', %i[a])
    end

    it 'compares owners with the given test' do
      assert_equal '<a>xy</a>', paint('xy', %i[a b], same: ->(_left, _right) { true })
    end
  end
end
