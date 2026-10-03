# frozen_string_literal: true

require 'test_helper'
class GlobexProbeProvider < Riffer::Providers::Mock; end # rubocop:disable Rig/NoInheritance -- riffer builds providers through Riffer::Providers::Base subclasses

describe Riffer::Rig::Providers do
  let(:globex_setup) do
    Riffer::Rig::ProviderSetup.from(
      url: 'https://globex.example.com/keys',
      fields: [{ name: :api_key, env: ['GLOBEX_PROBE_API_KEY'], secret: true, required: true }]
    )
  end

  after do
    Riffer::Rig::Providers.unregister(:globex_probe)
  end

  it 'registers the class factory with riffer\'s repository' do
    Riffer::Rig::Providers.register(:globex_probe, setup: globex_setup) { GlobexProbeProvider }

    assert_same GlobexProbeProvider, Riffer::Providers::Repository.find(:globex_probe)
  end

  it 'converts a setup hash and stores it' do
    Riffer::Rig::Providers.register(:globex_probe, setup: { fields: [{ name: :api_key, env: ['GLOBEX_PROBE_API_KEY'] }] }) { GlobexProbeProvider }

    assert_equal [:api_key], Riffer::Rig::Providers.setup(:globex_probe).fields.map(&:name)
  end

  it 'stores a ProviderSetup as given' do
    Riffer::Rig::Providers.register(:globex_probe, setup: globex_setup) { GlobexProbeProvider }

    assert_same globex_setup, Riffer::Rig::Providers.setup(:globex_probe)
  end

  it 'gives a setup-less registration no setup' do
    Riffer::Rig::Providers.register(:globex_probe) { GlobexProbeProvider }

    assert_nil Riffer::Rig::Providers.setup(:globex_probe)
  end

  it 'keeps a setup-less registration in the identifier list' do
    Riffer::Rig::Providers.register(:globex_probe) { GlobexProbeProvider }

    assert_includes Riffer::Rig::Providers.identifiers, :globex_probe
  end

  it 'lists the built-ins without mock plus the registered identifiers' do
    Riffer::Rig::Providers.register(:globex_probe, setup: globex_setup) { GlobexProbeProvider }

    assert_equal(
      %i[amazon_bedrock anthropic azure_openai gemini openai openrouter globex_probe],
      Riffer::Rig::Providers.identifiers
    )
  end

  it 'replaces the setup when registered again' do
    Riffer::Rig::Providers.register(:globex_probe, setup: globex_setup) { GlobexProbeProvider }
    Riffer::Rig::Providers.register(:globex_probe, setup: { fields: [{ name: :token, env: ['GLOBEX_PROBE_TOKEN'] }] }) { GlobexProbeProvider }

    assert_equal [:token], Riffer::Rig::Providers.setup(:globex_probe).fields.map(&:name)
  end

  it 'removes the registration on unregister' do
    Riffer::Rig::Providers.register(:globex_probe, setup: globex_setup) { GlobexProbeProvider }
    Riffer::Rig::Providers.unregister(:globex_probe)

    assert_nil Riffer::Providers::Repository.find(:globex_probe)
  end

  it 'removes the setup on unregister' do
    Riffer::Rig::Providers.register(:globex_probe, setup: globex_setup) { GlobexProbeProvider }
    Riffer::Rig::Providers.unregister(:globex_probe)

    assert_nil Riffer::Rig::Providers.setup(:globex_probe)
  end

  it 'drops the identifier from the list on unregister' do
    Riffer::Rig::Providers.register(:globex_probe, setup: globex_setup) { GlobexProbeProvider }
    Riffer::Rig::Providers.unregister(:globex_probe)

    refute_includes Riffer::Rig::Providers.identifiers, :globex_probe
  end
end
