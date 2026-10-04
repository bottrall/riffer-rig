# frozen_string_literal: true

require 'fileutils'
require 'json'

class Riffer::Rig::Stores::JSONL
  HEADER_VERSION = 1 #: Integer

  # @rbs @home: String
  # @rbs @paths: Hash[String, String]

  # @rbs home: String
  # @rbs return: void
  def initialize(home: Dir.home)
    @home = home
    @paths = {}
  end

  # @rbs id: String
  # @rbs entry: Hash[Symbol, untyped]
  # @rbs return: void
  def append(id, entry)
    File.write(path_for(id, entry), "#{JSON.generate(entry)}\n", mode: 'a')
  end

  # @rbs id: String
  # @rbs return: Array[Hash[Symbol, untyped]]
  def read(id)
    path = find(id)
    return [] unless path

    File.foreach(path).filter_map { |line| parse(line) }
  end

  # @rbs cwd: String?
  # @rbs return: Array[Hash[Symbol, untyped]]
  def list(cwd: nil)
    headers = Dir.glob(File.join(root, '*', '*.jsonl')).filter_map { |path| header_of(path) }
    cwd ? headers.select { |header| header[:cwd] == cwd } : headers
  end

  # @rbs id: String
  # @rbs return: void
  def delete(id)
    path = find(id)
    return unless path

    File.delete(path)
    @paths.delete(id)
  end

  private

  # @rbs return: String
  def root
    File.join(@home, '.riffer', 'sessions')
  end

  # @rbs id: String
  # @rbs entry: Hash[Symbol, untyped]
  # @rbs return: String
  def path_for(id, entry)
    @paths.fetch(id) do
      path = entry[:type] == 'header' ? new_path(id, entry.fetch(:cwd)) : find(id)
      raise ArgumentError, "no session file for #{id}" unless path

      @paths[id] = path
    end
  end

  # @rbs id: String
  # @rbs cwd: String
  # @rbs return: String
  def new_path(id, cwd)
    dir = File.join(root, slug(cwd))
    FileUtils.mkdir_p(dir)
    File.join(dir, "#{id}.jsonl")
  end

  # @rbs path: String
  # @rbs return: Hash[Symbol, untyped]?
  def header_of(path)
    line = File.foreach(path).first
    entry = parse(line) if line
    entry if entry.is_a?(Hash) && entry[:type] == 'header'
  end

  # @rbs id: String
  # @rbs return: String?
  def find(id)
    @paths.fetch(id) do
      found = Dir.glob(File.join(root, '*', "#{id}.jsonl")).first
      @paths[id] = found if found
      found
    end
  end

  # The slug groups a cwd's sessions for listing; it is not the truth — the
  # header's cwd is, so two cwd strings that slug alike share a directory. A
  # bare "." or ".." is collapsed so the file stays inside the sessions tree.
  # @rbs cwd: String
  # @rbs return: String
  def slug(cwd)
    slug = cwd.gsub(/[^A-Za-z0-9._-]+/, '-').gsub(/\A-+|-+\z/, '')
    slug.empty? || slug.match?(/\A\.{1,2}\z/) ? '-' : slug
  end

  # @rbs line: String
  # @rbs return: Hash[Symbol, untyped]?
  def parse(line)
    JSON.parse(line, symbolize_names: true)
  rescue JSON::ParserError
    nil
  end
end
