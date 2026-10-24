# frozen_string_literal: true

require 'test_helper'
require 'rubocop'
require_relative '../../../../rubocop/cop/rig/no_data_define'

describe RuboCop::Cop::Rig::NoDataDefine do
  def offenses(source)
    cop = RuboCop::Cop::Rig::NoDataDefine.new(RuboCop::Config.new)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, 'lib/example.rb')
    RuboCop::Cop::Commissioner.new([cop]).investigate(processed).offenses
  end

  it 'flags Data.define' do
    assert_equal [1], offenses("Point = Data.define(:x, :y)\n").map(&:line)
  end

  it 'flags a top-level-qualified Data.define' do
    assert_equal [1], offenses("Point = ::Data.define(:x, :y)\n").map(&:line)
  end

  it 'flags Struct.new' do
    assert_equal [1], offenses("Point = Struct.new(:x, :y)\n").map(&:line)
  end

  it 'allows a plain object' do
    assert_empty offenses("point = Point.new(x: 1, y: 2)\n")
  end
end
