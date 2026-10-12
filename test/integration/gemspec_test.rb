# frozen_string_literal: true

require 'test_helper'

describe 'the gemspec' do
  root = File.expand_path('../..', __dir__)

  it 'depends on no provider SDK' do
    spec = Gem::Specification.load(File.join(root, 'riffer-rig.gemspec'))
    sdks = spec.runtime_dependencies.select do |dependency|
      %w[anthropic openai aws-sdk-bedrockruntime].include?(dependency.name)
    end

    assert_empty sdks
  end
end
