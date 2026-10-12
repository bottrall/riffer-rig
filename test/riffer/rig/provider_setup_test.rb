# frozen_string_literal: true

require 'test_helper'
class GlobexSetupProvider < Riffer::Providers::Mock; end # rubocop:disable Rig/NoInheritance -- riffer builds providers through Riffer::Providers::Base subclasses

describe Riffer::Rig::ProviderSetup do
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

  describe '#initialize' do
    it 'offers no credential chain by default' do
      refute Riffer::Rig::ProviderSetup.new(fields: []).chain
    end

    it 'has no SDK by default' do
      assert_nil Riffer::Rig::ProviderSetup.new(fields: []).sdk
    end

    it 'freezes the sdk pair' do
      assert_predicate Riffer::Rig::ProviderSetup.new(fields: [], sdk: ['acme-sdk', '~> 1.0']).sdk, :frozen?
    end

    it 'freezes the fields' do
      assert_predicate Riffer::Rig::ProviderSetup.new(fields: []).fields, :frozen?
    end

    it 'freezes a setup' do
      assert_predicate Riffer::Rig::ProviderSetup.new(fields: []), :frozen?
    end
  end

  describe 'AWS_SHARED_CONFIG_REGION' do
    it 'has no region when the AWS SDK is not installed' do
      assert_nil Riffer::Rig::ProviderSetup::AWS_SHARED_CONFIG_REGION.call
    end
  end

  describe 'TABLE' do
    it 'names only settable fields of the provider config' do
      unknown = Riffer::Rig::ProviderSetup::TABLE.flat_map do |identifier, setup|
        provider_config = Riffer.config.public_send(identifier)
        setup.fields.map(&:name).reject { |name| provider_config.respond_to?(:"#{name}=") }
      end

      assert_empty unknown
    end
  end

  describe '#missing_fields' do
    let(:acme_setup) do
      Riffer::Rig::ProviderSetup.new(
        fields: [
          Riffer::Rig::ProviderSetup::Field.new(
            name: :region, env: %w[ACME_REGION ACME_DEFAULT_REGION], secret: false, required: true
          ),
          Riffer::Rig::ProviderSetup::Field.new(name: :api_key, env: ['ACME_API_KEY'], secret: true, required: true)
        ]
      )
    end

    it 'is empty when nothing is missing' do
      assert_equal '', acme_setup.missing_fields([])
    end

    it 'leaves out the fields that are not missing' do
      assert_equal 'api_key (ACME_API_KEY)', acme_setup.missing_fields([:api_key])
    end

    it 'ignores a missing name the setup has no field for' do
      assert_equal 'api_key (ACME_API_KEY)', acme_setup.missing_fields(%i[api_key endpoint])
    end

    it 'joins the env alternatives of a field' do
      assert_equal 'region (ACME_REGION or ACME_DEFAULT_REGION)', acme_setup.missing_fields([:region])
    end

    it 'lists the missing fields in field order' do
      assert_equal(
        'region (ACME_REGION or ACME_DEFAULT_REGION), api_key (ACME_API_KEY)',
        acme_setup.missing_fields(%i[api_key region])
      )
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

  describe '.registered_setup' do
    it 'prefers a registered setup over the table' do
      Riffer::Rig::Providers.register(:globex_setup, setup: registered_setup) { GlobexSetupProvider }

      assert_same registered_setup, Riffer::Rig::ProviderSetup.registered_setup(:globex_setup)
    end

    it 'looks an entry up by string identifier' do
      assert_same Riffer::Rig::ProviderSetup::TABLE[:anthropic], Riffer::Rig::ProviderSetup.registered_setup('anthropic')
    end

    it 'returns nil for an unknown identifier' do
      assert_nil Riffer::Rig::ProviderSetup.registered_setup(:acme)
    end
  end

  describe '.for' do
    it 'prefers a registered setup over the generic fallback' do
      Riffer::Rig::Providers.register(:globex_setup, setup: registered_setup) { GlobexSetupProvider }

      assert_same registered_setup, Riffer::Rig::ProviderSetup.for(:globex_setup)
    end

    it 'returns the built-in setup' do
      assert_same Riffer::Rig::ProviderSetup::TABLE[:gemini], Riffer::Rig::ProviderSetup.for(:gemini)
    end

    it 'leaves a registered provider without a setup on the generic fallback' do
      Riffer::Rig::Providers.register(:globex_setup) { GlobexSetupProvider }

      assert_equal(
        [[:api_key, ['GLOBEX_SETUP_API_KEY']]],
        Riffer::Rig::ProviderSetup.for(:globex_setup).fields.map { |field| [field.name, field.env] }
      )
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
  end
end
