# frozen_string_literal: true

module Riffer::Rig::Credentials::ProviderFields
  extend self

  # @rbs identifier: String
  # @rbs path: String
  # @rbs return: (Hash[String, String] | String)
  def read(identifier, path:)
    source = Riffer::Rig::Settings::File.read(path)
    return source if source.is_a?(String)

    Riffer::Rig::Settings::Document.new(source).providers[identifier] || {}
  end

  # @rbs identifier: String
  # @rbs fields: Hash[String, String]
  # @rbs path: String
  # @rbs return: String?
  def store(identifier, fields, path:)
    update(path) do |providers|
      providers.merge(identifier => fields) { |_identifier, stored, given| stored.merge(given) }
    end
  end

  # @rbs identifier: String
  # @rbs path: String
  # @rbs return: String?
  def remove(identifier, path:)
    update(path) { |providers| providers.except(identifier) }
  end

  private

  # @rbs path: String
  # @rbs &: (Hash[String, Hash[String, String]]) -> Hash[String, Hash[String, String]]
  # @rbs return: String?
  def update(path)
    Riffer::Rig::Settings::File.update(path) do |source|
      current = Riffer::Rig::Settings::Document.new(source).providers
      providers = yield current
      next source if providers == current

      providers.empty? ? source.except(:providers) : source.merge(providers: providers)
    end
  end
end
