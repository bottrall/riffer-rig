# frozen_string_literal: true

require 'test_helper'
require 'rubocop'
require_relative '../../../../rubocop/cop/rig/require_disable_reason'

describe RuboCop::Cop::Rig::RequireDisableReason do
  def offenses(source)
    config = RuboCop::Config.new
    cop = RuboCop::Cop::Rig::RequireDisableReason.new(config)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, 'lib/example.rb')
    # Parsing a disable directive reads the registry and config, and without
    # them the commissioner swallows the error and reports no offenses.
    processed.registry = RuboCop::Cop::Registry.global
    processed.config = config
    RuboCop::Cop::Commissioner.new([cop]).investigate(processed).offenses
  end

  it 'flags a disable without a reason' do
    assert_equal [1], offenses("run # rubocop:disable Style/Foo\n").map(&:line)
  end

  it 'flags a todo without a reason' do
    assert_equal [1], offenses("# rubocop:todo Style/Foo\n").map(&:line)
  end

  it 'allows a disable with a reason' do
    assert_empty offenses("run # rubocop:disable Style/Foo -- the API demands it\n")
  end

  it 'ignores an enable directive' do
    assert_empty offenses("# rubocop:enable Style/Foo\n")
  end
end
