# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Recipes do
  it "covers riffer's six providers" do
    expected = %i[anthropic openai gemini openrouter azure_openai amazon_bedrock]

    assert_equal expected, Riffer::Rig::Recipes::TABLE.keys
  end

  it 'names only members of the provider config' do
    unknown = Riffer::Rig::Recipes::TABLE.flat_map do |identifier, recipe|
      recipe[:fields].map { |field| field[:name] } - Riffer.config.public_send(identifier).members
    end

    assert_empty unknown
  end

  it 'looks a recipe up by string identifier' do
    assert_same Riffer::Rig::Recipes::TABLE[:anthropic], Riffer::Rig::Recipes['anthropic']
  end

  it 'returns nil from [] for an unknown identifier' do
    assert_nil Riffer::Rig::Recipes[:acme]
  end

  it 'returns the built-in recipe from for' do
    assert_same Riffer::Rig::Recipes::TABLE[:gemini], Riffer::Rig::Recipes.for(:gemini)
  end

  it 'returns the generic fallback from for for an unknown identifier' do
    expected = { fields: [{ name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true }] }

    assert_equal expected, Riffer::Rig::Recipes.for(:acme)
  end

  it 'never prompts for the OpenAI base_url' do
    base_url = Riffer::Rig::Recipes[:openai][:fields].find { |field| field[:name] == :base_url }

    refute base_url[:required]
  end

  it 'marks Bedrock as offering the credential chain' do
    assert Riffer::Rig::Recipes[:amazon_bedrock][:chain]
  end

  it 'reads the Bedrock region from both AWS env vars' do
    region = Riffer::Rig::Recipes[:amazon_bedrock][:fields].find { |field| field[:name] == :region }

    assert_equal %w[AWS_REGION AWS_DEFAULT_REGION], region[:env]
  end

  it 'gives the Bedrock region a fallback' do
    region = Riffer::Rig::Recipes[:amazon_bedrock][:fields].find { |field| field[:name] == :region }

    assert_respond_to region[:fallback], :call
  end
end
