# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Hosts::NonInteractive do
  let(:host) { Class.new { include Riffer::Rig::Hosts::NonInteractive }.new }

  it 'answers nil from ask' do
    assert_nil host.ask('Which model?', options: %w[a b], secret: true)
  end

  it 'answers false from confirm' do
    refute host.confirm('sure?')
  end

  it 'yields from progress' do
    yielded = false
    host.progress('working') { yielded = true }

    assert yielded
  end

  it 'accepts progress without a block' do
    assert_nil host.progress('working')
  end
end
