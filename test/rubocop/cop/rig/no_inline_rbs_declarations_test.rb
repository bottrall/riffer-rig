# frozen_string_literal: true

require 'test_helper'
require 'rubocop'
require_relative '../../../../rubocop/cop/rig/no_inline_rbs_declarations'

describe RuboCop::Cop::Rig::NoInlineRbsDeclarations do
  def offenses(source)
    cop = RuboCop::Cop::Rig::NoInlineRbsDeclarations.new(RuboCop::Config.new)
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, 'lib/example.rb')
    RuboCop::Cop::Commissioner.new([cop]).investigate(processed).offenses
  end

  it 'flags an @rbs! declaration block' do
    source = <<~RUBY
      module Example
        # @rbs!
        #   type name = String
      end
    RUBY

    assert_equal [2], offenses(source).map(&:line)
  end

  it 'allows per-method @rbs annotations' do
    source = <<~RUBY
      # @rbs return: String
      def name = 'x'
    RUBY

    assert_empty offenses(source)
  end

  it 'tells the author where declarations belong' do
    assert_match %r{sig/manual/}, offenses("# @rbs!\n").first.message
  end
end
