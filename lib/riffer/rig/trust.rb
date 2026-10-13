# frozen_string_literal: true

module Riffer::Rig::Trust
  extend self

  # @rbs path: String
  # @rbs return: (Hash[String, bool] | String)
  def read(path)
    document = Riffer::Rig::Support::JsonFile.read(path)
    document.is_a?(String) ? document : decisions(document)
  end

  # @rbs path: String
  # @rbs file: String
  # @rbs decision: bool
  # @rbs return: String?
  def store(path, file, decision)
    Riffer::Rig::Support::JsonFile.update(path) { |document| decisions(document).merge(file => decision) }
  end

  private

  # @rbs document: Hash[untyped, untyped]
  # @rbs return: Hash[String, bool]
  def decisions(document)
    document.select { |_file, decision| [true, false].include?(decision) }
  end
end
