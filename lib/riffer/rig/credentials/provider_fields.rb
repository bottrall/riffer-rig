# frozen_string_literal: true

module Riffer::Rig::Credentials::ProviderFields
  extend self

  # @rbs identifier: String
  # @rbs path: String
  # @rbs return: Hash[String, String]
  def read(identifier, path:)
    Riffer::Rig::Settings::Document.new(Riffer::Rig::Settings::File.read(path)).providers[identifier] || {}
  end

  # @rbs identifier: String
  # @rbs fields: Hash[String, String]
  # @rbs path: String
  # @rbs return: void
  def store(identifier, fields, path:)
    update(path) do |providers|
      providers.merge(identifier => fields) { |_identifier, stored, given| stored.merge(given) }
    end
  end

  # @rbs identifier: String
  # @rbs path: String
  # @rbs return: void
  def remove(identifier, path:)
    update(path) { |providers| providers.except(identifier) }
  end

  private

  # @rbs path: String
  # @rbs &: (Hash[String, Hash[String, String]]) -> Hash[String, Hash[String, String]]
  # @rbs return: void
  def update(path)
    source = Riffer::Rig::Settings::File.read(path)
    current = Riffer::Rig::Settings::Document.new(source).providers
    providers = yield current
    return if providers == current

    document = providers.empty? ? source.except(:providers) : source.merge(providers: providers)
    Riffer::Rig::Support::JsonFile.write(path, document)
  end
end
