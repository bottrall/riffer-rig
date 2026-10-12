# frozen_string_literal: true

require 'json'
require 'fileutils'

module Riffer::Rig::Support::JsonFile
  extend self

  # @rbs path: String
  # @rbs symbolize_names: bool
  # @rbs return: Hash[untyped, untyped]
  def read(path, symbolize_names: false)
    return {} unless File.file?(path)

    document = JSON.parse(File.read(path), symbolize_names: symbolize_names)
    document.is_a?(Hash) ? document : {}
  rescue JSON::ParserError
    {}
  end

  # @rbs path: String
  # @rbs document: Hash[untyped, untyped]
  # @rbs mode: Integer
  # @rbs return: void
  def write(path, document, mode: 0o666)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    File.open(path, 'w', mode) { |file| file.write(JSON.pretty_generate(document)) }
  end
end
