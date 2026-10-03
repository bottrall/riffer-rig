# frozen_string_literal: true

require 'test_helper'
class GlobexSetupProvider < Riffer::Providers::Mock; end # rubocop:disable Rig/NoInheritance -- riffer builds providers through Riffer::Providers::Base subclasses

describe Riffer::Rig::ProviderSetup do
  it "covers riffer's six providers" do
    expected = %i[anthropic openai gemini openrouter azure_openai amazon_bedrock]

    assert_equal expected, Riffer::Rig::ProviderSetup::TABLE.keys
  end

  it 'names only settable fields of the provider config' do
    unknown = Riffer::Rig::ProviderSetup::TABLE.flat_map do |identifier, setup|
      provider_config = Riffer.config.public_send(identifier)
      setup.fields.map(&:name).reject { |name| provider_config.respond_to?(:"#{name}=") }
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

  it 'maps each provider to its SDK gem and requirement' do
    expected = {
      anthropic: ['anthropic', '~> 1.69'],
      openai: ['openai', '~> 0.80'],
      openrouter: ['openai', '~> 0.80'],
      azure_openai: ['openai', '~> 0.80'],
      gemini: nil,
      amazon_bedrock: ['aws-sdk-bedrockruntime', '~> 1.0']
    }

    assert_equal expected, Riffer::Rig::ProviderSetup::TABLE.transform_values(&:sdk)
  end

  it 'gives the generic fallback entry no SDK' do
    assert_nil Riffer::Rig::ProviderSetup.for(:acme).sdk
  end

  it 'freezes the sdk pair' do
    assert_predicate Riffer::Rig::ProviderSetup[:anthropic].sdk, :frozen?
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

  describe 'a registered setup' do
    let(:registered_setup) do
      Riffer::Rig::ProviderSetup.new(
        fields: [Riffer::Rig::ProviderSetup::Field.new(
          name: :api_key,
          env: ['GLOBEX_SETUP_API_KEY'],
          secret: true,
          required: true
        )]
      )
    end

    after do
      Riffer::Rig::Providers.unregister(:globex_setup)
    end

    it 'wins the [] lookup over the table' do
      Riffer::Rig::Providers.register(:globex_setup, setup: registered_setup) { GlobexSetupProvider }

      assert_same registered_setup, Riffer::Rig::ProviderSetup[:globex_setup]
    end

    it 'wins the for lookup over the generic fallback' do
      Riffer::Rig::Providers.register(:globex_setup, setup: registered_setup) { GlobexSetupProvider }

      assert_same registered_setup, Riffer::Rig::ProviderSetup.for(:globex_setup)
    end

    it 'leaves a registered provider without a setup on the generic fallback' do
      Riffer::Rig::Providers.register(:globex_setup) { GlobexSetupProvider }

      assert_equal [['GLOBEX_SETUP_API_KEY']], Riffer::Rig::ProviderSetup.for(:globex_setup).fields.map(&:env)
    end
  end

  describe '.from' do
    def from(**hash)
      Riffer::Rig::ProviderSetup.from(**hash)
    end

    it 'builds the fields' do
      setup = from(fields: [{ name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true }])

      assert_equal(
        [[:api_key, ['ACME_API_KEY'], true, true, nil]],
        setup.fields.map { |field| [field.name, field.env, field.secret, field.required, field.fallback] }
      )
    end

    it 'defaults the field flags' do
      setup = from(fields: [{ name: :endpoint, env: ['ACME_ENDPOINT'] }])

      assert_equal([[false, false, nil]], setup.fields.map { |field| [field.secret, field.required, field.fallback] })
    end

    it 'reads the url' do
      setup = from(url: 'https://example.com/keys', fields: [])

      assert_equal 'https://example.com/keys', setup.url
    end

    it 'defaults the chain flag' do
      setup = from(fields: [])

      refute setup.chain
    end

    it 'reads the sdk pair' do
      setup = from(sdk: ['acme-sdk', '~> 1.0'], fields: [])

      assert_equal ['acme-sdk', '~> 1.0'], setup.sdk
    end

    it 'freezes the setup' do
      setup = from(fields: [{ name: :api_key, env: ['ACME_API_KEY'] }])

      assert_predicate setup, :frozen?
    end
  end
end
