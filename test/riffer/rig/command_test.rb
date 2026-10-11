# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Command do
  it 'carries its name, description and extension' do
    command = Riffer::Rig::Command.new('log', description: 'Recent commits', extension: :git) { |_ctx| nil }

    assert_equal ['log', 'Recent commits', :git], [command.name, command.description, command.extension]
  end

  it 'passes the context to its block' do
    received = nil
    command = Riffer::Rig::Command.new('log', description: 'Recent commits', extension: :git) { |ctx| received = ctx }
    ctx = Object.new
    command.call(ctx)

    assert_same ctx, received
  end

  it 'is frozen' do
    command = Riffer::Rig::Command.new('log', description: 'Recent commits', extension: :git) { |_ctx| nil }

    assert_predicate command, :frozen?
  end
end
