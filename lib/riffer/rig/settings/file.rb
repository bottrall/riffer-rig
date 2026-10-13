# frozen_string_literal: true

module Riffer::Rig::Settings::File
  extend self

  PATH = ::File.expand_path('~/.riffer/settings.json') #: String

  # @rbs path: String
  # @rbs return: (Hash[Symbol, untyped] | String)
  def read(path)
    Riffer::Rig::Support::JsonFile.read(path, symbolize_names: true)
  end

  # @rbs path: String
  # @rbs &: (Hash[Symbol, untyped]) -> Hash[Symbol, untyped]
  # @rbs return: String?
  def update(path, &)
    Riffer::Rig::Support::JsonFile.update(path, symbolize_names: true, &)
  end

  # @rbs model: String
  # @rbs path: String
  # @rbs return: String?
  def store_model(model, path: PATH)
    update(path) { |document| document.merge(model: model) }
  end
end
