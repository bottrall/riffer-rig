# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Loader::Options do
  it 'defaults the flags to enabled' do
    assert Riffer::Rig::Loader::Options.new.extensions
    assert Riffer::Rig::Loader::Options.new.skills
    assert Riffer::Rig::Loader::Options.new.agents_md
  end

  it 'defaults the model and tools to nil' do
    assert_nil Riffer::Rig::Loader::Options.new.model
    assert_nil Riffer::Rig::Loader::Options.new.tools
  end

  it 'defaults max_steps to the runtime default of unset' do
    assert_nil Riffer::Rig::Loader::Options.new.max_steps
  end

  it 'carries the given values' do
    options = Riffer::Rig::Loader::Options.new(model: 'gpt-5', tools: %w[read], extensions: false)

    assert_equal 'gpt-5', options.model
    assert_equal %w[read], options.tools
    refute options.extensions
  end

  it 'is frozen' do
    assert_predicate Riffer::Rig::Loader::Options.new, :frozen?
  end
end
