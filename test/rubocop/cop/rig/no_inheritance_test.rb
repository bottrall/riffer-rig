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

  it 'flags a class inheriting from a rig class' do
    assert_equal [1], offenses("class Fake < Riffer::Rig::Hosts::Null; end\n").map(&:line)
  end

  it 'allows a framework-mandated riffer parent' do
    assert_empty offenses("class Read < Riffer::Tool; end\n")
  end

  it 'allows a top-level-qualified riffer parent' do
    assert_empty offenses("class Read < ::Riffer::Tool; end\n")
  end

  it 'allows an error subclass' do
    assert_empty offenses("class BusyError < StandardError; end\n")
  end

  it 'allows a class without a parent' do
    assert_empty offenses("class Plain; end\n")
  end
end
