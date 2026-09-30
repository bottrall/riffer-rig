# frozen_string_literal: true

require 'test_helper'
require 'rubocop'
require_relative '../../../../rubocop/cop/rig/no_mocking'

describe RuboCop::Cop::Rig::NoMocking do
  def offenses(source)
    cop = RuboCop::Cop::Rig::NoMocking.new(RuboCop::Config.new)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, 'test/example_test.rb')
    RuboCop::Cop::Commissioner.new([cop]).investigate(processed).offenses
  end

  it 'flags Minitest::Mock' do
    assert_equal [1], offenses("host = Minitest::Mock.new\n").map(&:line)
  end

  it 'flags stub' do
    assert_equal [1], offenses("Time.stub(:now, 0) { run }\n").map(&:line)
  end

  it 'allows an injected fake' do
    assert_empty offenses("runtime = Runtime.new(host: FakeHost.new)\n")
  end
end
