# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::ProviderSetup::Field do
  let(:field) { Riffer::Rig::ProviderSetup::Field.new(name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true) }

  it 'has no fallback by default' do
    assert_nil field.fallback
  end

  it 'keeps the fallback it is given' do
    fallback = -> { 'us-east-1' }
    field = Riffer::Rig::ProviderSetup::Field.new(
      name: :region, env: ['ACME_REGION'], secret: false, required: false, fallback: fallback
    )

    assert_same fallback, field.fallback
  end

  it 'is frozen' do
    assert_predicate field, :frozen?
  end

  it 'freezes the env var names' do
    assert_predicate field.env, :frozen?
  end
end
