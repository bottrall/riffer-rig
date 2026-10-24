# frozen_string_literal: true

require 'test_helper'
require 'rubocop'
require_relative '../../../../rubocop/cop/rig/no_inheritance'

describe RuboCop::Cop::Rig::NoInheritance do
  def offenses(source)
    cop = RuboCop::Cop::Rig::NoInheritance.new(RuboCop::Config.new)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, 'lib/example.rb')
    RuboCop::Cop::Commissioner.new([cop]).investigate(processed).offenses
  end

  it 'allows a class without a parent' do
    assert_empty offenses("class Plain; end\n")
  end

  it 'allows a framework-mandated riffer parent' do
    assert_empty offenses("class Read < Riffer::Tool; end\n")
  end

  it 'allows a top-level-qualified riffer parent' do
    assert_empty offenses("class Read < ::Riffer::Tool; end\n")
  end

  it 'allows Exception as a parent' do
    assert_empty offenses("class Signal < Exception; end\n")
  end

  it 'allows a StandardError subclass' do
    assert_empty offenses("class BusyError < StandardError; end\n")
  end

  it 'allows a subclass of a core StandardError descendant' do
    assert_empty offenses("class Invalid < ArgumentError; end\n")
  end

  it 'flags a subclass of a core error outside StandardError' do
    assert_equal [1], offenses("class Pending < NotImplementedError; end\n").map(&:line)
  end

  it 'flags a subclass of a loaded error class defined in Ruby' do
    assert_equal [1], offenses("class Broken < RuboCop::Error; end\n").map(&:line)
  end

  it 'flags a subclass of an error class the cop cannot resolve' do
    assert_equal [1], offenses("class Expired < Mcp::Auth::Error; end\n").map(&:line)
  end

  it 'flags a parent that is not a constant' do
    assert_equal [1], offenses("class Point < Struct.new(:x); end\n").map(&:line)
  end

  it 'flags a class inheriting from a rig class' do
    assert_equal [1], offenses("class Fake < Riffer::Rig::Hosts::Null; end\n").map(&:line)
  end
end
