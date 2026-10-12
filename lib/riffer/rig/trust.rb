# frozen_string_literal: true

module Riffer::Rig::Trust
  extend self

  # @rbs path: String
  # @rbs return: Hash[String, bool]
  def read(path)
    Riffer::Rig::Support::JsonFile.read(path).select { |_file, decision| [true, false].include?(decision) }
  end

  # @rbs path: String
  # @rbs file: String
  # @rbs decision: bool
  # @rbs return: void
  def store(path, file, decision)
    Riffer::Rig::Support::JsonFile.write(path, read(path).merge(file => decision))
  end
end
