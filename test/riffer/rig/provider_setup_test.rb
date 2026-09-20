# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::ProviderSetup do
  it "covers riffer's six providers" do
    expected = %i[anthropic openai gemini openrouter azure_openai amazon_bedrock]

    assert_equal expected, Riffer::Rig::ProviderSetup::TABLE.keys
  end

  it 'names only members of the provider config' do
    unknown = Riffer::Rig::ProviderSetup::TABLE.flat_map do |identifier, setup|
      setup.fields.map(&:name) - Riffer.config.public_send(identifier).members
    end

    assert_empty unknown
  end

  it 'looks an entry up by string identifier' do
    assert_same Riffer::Rig::ProviderSetup::TABLE[:anthropic], Riffer::Rig::ProviderSetup['anthropic']
  end

  it 'returns nil from [] for an unknown identifier' do
    assert_nil Riffer::Rig::ProviderSetup[:acme]
  end

  it 'returns the built-in setup from for' do
    assert_same Riffer::Rig::ProviderSetup::TABLE[:gemini], Riffer::Rig::ProviderSetup.for(:gemini)
  end

  it 'reads the generic fallback key from <IDENTIFIER>_API_KEY' do
    assert_equal [['ACME_API_KEY']], Riffer::Rig::ProviderSetup.for(:acme).fields.map(&:env)
  end

  it 'requires the generic fallback key' do
    assert Riffer::Rig::ProviderSetup.for(:acme).fields.all?(&:required)
  end

  it 'treats the generic fallback key as a secret' do
    assert Riffer::Rig::ProviderSetup.for(:acme).fields.all?(&:secret)
  end

  it 'offers no credential chain by default' do
    refute Riffer::Rig::ProviderSetup.for(:acme).chain
  end

  it 'freezes a setup' do
    assert_predicate Riffer::Rig::ProviderSetup.for(:acme), :frozen?
  end

  it 'freezes the fields' do
    assert_predicate Riffer::Rig::ProviderSetup.for(:acme).fields, :frozen?
  end

  it 'never prompts for the OpenAI base_url' do
    base_url = Riffer::Rig::ProviderSetup[:openai].fields.find { |field| field.name == :base_url }

    refute base_url.required
  end

  it 'marks Bedrock as offering the credential chain' do
    assert Riffer::Rig::ProviderSetup[:amazon_bedrock].chain
  end

  it 'reads the Bedrock region from both AWS env vars' do
    region = Riffer::Rig::ProviderSetup[:amazon_bedrock].fields.find { |field| field.name == :region }

    assert_equal %w[AWS_REGION AWS_DEFAULT_REGION], region.env
  end

  it 'gives the Bedrock region a fallback' do
    region = Riffer::Rig::ProviderSetup[:amazon_bedrock].fields.find { |field| field.name == :region }

    assert_respond_to region.fallback, :call
  end
end
