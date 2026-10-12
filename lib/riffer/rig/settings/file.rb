# frozen_string_literal: true

module Riffer::Rig::Settings::File
  extend self

  PATH = ::File.expand_path('~/.riffer/settings.json') #: String

  # @rbs path: String
  # @rbs return: Hash[Symbol, untyped]
  def read(path)
    Riffer::Rig::Support::JsonFile.read(path, symbolize_names: true)
  end

  # @rbs model: String
  # @rbs path: String
  # @rbs return: void
  def store_model(model, path: PATH)
    Riffer::Rig::Support::JsonFile.write(path, read(path).merge(model: model))
  end
end
