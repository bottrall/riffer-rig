# frozen_string_literal: true

module Riffer::Rig::Trust
  extend self

  # @rbs path: String
  # @rbs return: (Hash[String, Riffer::Rig::Trust::Decision] | String)
  def read(path)
    document = Riffer::Rig::Support::JsonFile.read(path)
    document.is_a?(String) ? document : decisions(document)
  end

  # @rbs path: String
  # @rbs file: String
  # @rbs decision: Riffer::Rig::Trust::Decision
  # @rbs return: String?
  def store(path, file, decision)
    Riffer::Rig::Support::JsonFile.update(path) do |document|
      decisions(document).transform_values(&:to_h).merge(file => decision.to_h)
    end
  end

  private

  # @rbs document: Hash[untyped, untyped]
  # @rbs return: Hash[String, Riffer::Rig::Trust::Decision]
  def decisions(document)
    document.filter_map do |file, entry|
      next unless decision?(entry)

      [file, Riffer::Rig::Trust::Decision.new(sha256: entry['sha256'], trusted: entry['trusted'])]
    end.to_h
  end

  # @rbs entry: untyped
  # @rbs return: bool
  def decision?(entry)
    entry.is_a?(Hash) && entry['sha256'].is_a?(String) && [true, false].include?(entry['trusted'])
  end
end
