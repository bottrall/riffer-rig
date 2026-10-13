# frozen_string_literal: true

require 'json'
require 'fileutils'

module Riffer::Rig::Support::JsonFile
  extend self

  # @rbs path: String
  # @rbs symbolize_names: bool
  # @rbs return: (Hash[untyped, untyped] | String)
  def read(path, symbolize_names: false)
    content = File.file?(path) ? File.read(path) : ''
    empty = {} #: Hash[untyped, untyped]
    return empty if content.b.strip.empty?

    document = JSON.parse(content, symbolize_names: symbolize_names)
    document.is_a?(Hash) ? document : "#{path} does not hold a JSON object"
  rescue JSON::ParserError => e
    # The parser's message quotes the text it stopped at, which in auth.json
    # can be a secret, so only the position is taken from it.
    ["#{path} is not valid JSON", e.message[/line \d+ column \d+\z/]].compact.join(' at ')
  end

  # @rbs path: String
  # @rbs symbolize_names: bool
  # @rbs mode: Integer?
  # @rbs &: (Hash[untyped, untyped]) -> Hash[untyped, untyped]
  # @rbs return: String?
  def update(path, symbolize_names: false, mode: nil)
    document = read(path, symbolize_names: symbolize_names)
    return document if document.is_a?(String)

    updated = yield document
    write(path, updated, mode: mode) unless updated == document
    nil
  end

  private

  # @rbs path: String
  # @rbs document: Hash[untyped, untyped]
  # @rbs mode: Integer?
  # @rbs return: void
  def write(path, document, mode:)
    FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
    File.open(path, 'w', mode || 0o666) do |file|
      # open applies its permissions only to a file it creates
      file.chmod(mode) if mode
      file.write(JSON.pretty_generate(document))
    end
  end
end
