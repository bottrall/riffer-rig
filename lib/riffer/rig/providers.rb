# frozen_string_literal: true

module Riffer::Rig::Providers
  extend self

  # Upstream candidate: riffer's Repository exposes no listing of extension
  # registrations and stores no credential setups, so this registry mirrors
  # what the provider seam registers.
  # @rbs @setups: Hash[Symbol, Riffer::Rig::ProviderSetup?]
  @setups = {} #: Hash[Symbol, Riffer::Rig::ProviderSetup?]

  # @rbs identifier: String | Symbol
  # @rbs setup: Riffer::Rig::ProviderSetup | Hash[Symbol, untyped]?
  # @rbs &block: () -> singleton(::Riffer::Providers::Base)
  # @rbs return: void
  def register(identifier, setup: nil, &)
    ::Riffer::Providers::Repository.register(identifier, &)
    @setups[identifier.to_sym] = setup && normalize(setup)
    nil
  end

  # @rbs identifier: String | Symbol
  # @rbs return: void
  def unregister(identifier)
    ::Riffer::Providers::Repository.unregister(identifier)
    @setups.delete(identifier.to_sym)
    nil
  end

  # @rbs identifier: String | Symbol
  # @rbs return: Riffer::Rig::ProviderSetup?
  def setup(identifier)
    @setups[identifier.to_sym]
  end

  # @rbs return: Array[Symbol]
  def identifiers
    (::Riffer::Providers::Repository::REPO.keys - [:mock]) | @setups.keys
  end

  private

  # @rbs setup: Riffer::Rig::ProviderSetup | Hash[Symbol, untyped]
  # @rbs return: Riffer::Rig::ProviderSetup
  def normalize(setup)
    setup.is_a?(::Riffer::Rig::ProviderSetup) ? setup : ::Riffer::Rig::ProviderSetup.from(setup)
  end
end
