# frozen_string_literal: true

require 'json'
require 'fileutils'

module Riffer::Rig::Trust
  extend self

  # @rbs path: String
  # @rbs return: Hash[String, bool]
  def read(path)
    return {} unless File.file?(path)

    source = JSON.parse(File.read(path))
    source.is_a?(Hash) ? source.select { |_file, decision| [true, false].include?(decision) } : {}
  rescue JSON::ParserError
    {}
  end

  # @rbs path: String
  # @rbs file: String
  # @rbs decision: bool
  # @rbs return: void
  def store(path, file, decision)
    write(path, read(path).merge(file => decision))
  end

  private

  # @rbs path: String
  # @rbs document: Hash[String, bool]
  # @rbs return: void
  def write(path, document)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    File.write(path, JSON.pretty_generate(document))
  end
end
