# frozen_string_literal: true

module Riffer::Rig::Loader::Credentials
  extend self

  # @rbs provider: String
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs env: Riffer::Rig::Env
  # @rbs config: Riffer::Config
  # @rbs auth_path: String
  # @rbs settings_path: String
  # @rbs return: (Hash[Symbol, String] | String)
  def install(provider, host:, env:, config:, auth_path:, settings_path:)
    resolution = Riffer::Rig::Credentials.install(provider, host:, env:, config:, auth_path:, settings_path:)
    return resolution if resolution.is_a?(String)
    return resolution.values if resolution.missing.empty?

    setup = Riffer::Rig::ProviderSetup.for(provider)
    "#{provider} has no #{setup.missing_fields(resolution.missing)}; " \
      'set it in the environment or run riffer interactively to paste it' \
      "#{" (create one at #{setup.url})" if setup.url}"
  end
end
