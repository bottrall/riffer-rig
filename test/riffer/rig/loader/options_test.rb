# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Loader::Options do
  it 'defaults to enabled flags and no overrides' do
    options = Riffer::Rig::Loader::Options.new

    assert_equal [true, true, true, nil, nil, nil, nil],
                 [options.extensions, options.skills, options.agents_md,
                  options.model, options.reasoning, options.tools, options.max_steps]
  end

  it 'carries the given values' do
    options = Riffer::Rig::Loader::Options.new(model: 'gpt-5', reasoning: 'high', tools: %w[read], extensions: false)

    assert_equal ['gpt-5', 'high', %w[read], false],
                 [options.model, options.reasoning, options.tools, options.extensions]
  end

  it 'freezes the given tools' do
    assert_predicate Riffer::Rig::Loader::Options.new(tools: %w[read]).tools, :frozen?
  end

  it 'is frozen' do
    assert_predicate Riffer::Rig::Loader::Options.new, :frozen?
  end
end
