# frozen_string_literal: true

module Riffer::Rig::Settings::File
  extend self

  PATH = Riffer::Rig::Directories.riffer(Dir.home, 'settings.json') #: String

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
  def store_model(model, path:)
    update(path) { |document| document.merge(model: model) }
  end

  # @rbs level: String
  # @rbs path: String
  # @rbs return: String?
  def store_reasoning(level, path:)
    update(path) { |document| document.merge(reasoning: level) }
  end
end
