# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Command do
  it 'splits an invocation into its name and the text after it' do
    invocation = Riffer::Rig::Command::INVOCATION.match('/skill:review focus on lib/')

    assert_equal ['skill:review', 'focus on lib/'], invocation&.captures
  end

  it 'matches no text without a leading slash' do
    assert_nil Riffer::Rig::Command::INVOCATION.match('review /skill:review')
  end

  it 'carries its name, description and extension' do
    command = Riffer::Rig::Command.new('log', description: 'Recent commits', extension: :git) { |_ctx| nil }

    assert_equal ['log', 'Recent commits', :git], [command.name, command.description, command.extension]
  end

  it 'is frozen' do
    command = Riffer::Rig::Command.new('log', description: 'Recent commits', extension: :git) { |_ctx| nil }

    assert_predicate command, :frozen?
  end

  it 'passes the context to its block' do
    received = nil
    command = Riffer::Rig::Command.new('log', description: 'Recent commits', extension: :git) { |ctx| received = ctx }
    ctx = Object.new
    command.call(ctx)

    assert_same ctx, received
  end
end
