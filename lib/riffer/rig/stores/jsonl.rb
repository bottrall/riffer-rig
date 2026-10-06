# frozen_string_literal: true

require 'fileutils'
require 'json'

class Riffer::Rig::Stores::JSONL
  HEADER_VERSION = 1 #: Integer

  ENTRY_TYPES = {
    Riffer::Rig::Stores::Header::TYPE => Riffer::Rig::Stores::Header,
    Riffer::Rig::Stores::MessageEntry::TYPE => Riffer::Rig::Stores::MessageEntry,
    Riffer::Rig::Stores::ModelEntry::TYPE => Riffer::Rig::Stores::ModelEntry,
    Riffer::Rig::Stores::SkillEntry::TYPE => Riffer::Rig::Stores::SkillEntry
  }.freeze #: Hash[String, Riffer::Rig::Stores::entry_type]

  # @rbs @home: String
  # @rbs @paths: Hash[String, String]

  # @rbs home: String
  # @rbs return: void
  def initialize(home: Dir.home)
    @home = home
    @paths = {}
  end

  # @rbs id: String
  # @rbs entry: Riffer::Rig::Stores::entry
  # @rbs return: void
  def append(id, entry)
    File.write(path_for(id, entry), "#{JSON.generate(entry.to_h)}\n", mode: 'a')
  end

  # @rbs id: String
  # @rbs return: Array[Riffer::Rig::Stores::entry]
  def read(id)
    path = find(id)
    return [] unless path

    File.foreach(path).filter_map { |line| entry_of(line) }
  end

  # @rbs cwd: String?
  # @rbs return: Array[::Riffer::Rig::Stores::Header]
  def list(cwd: nil)
    headers = Dir.glob(File.join(root, '*', '*.jsonl')).filter_map do |path|
      # Seeding the path cache here keeps picking the most recently updated
      # session one mtime per header instead of one glob.
      @paths[File.basename(path, '.jsonl')] = path
      header_of(path)
    end
    cwd ? headers.select { |header| header.cwd == cwd } : headers
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
  # @rbs entry: Riffer::Rig::Stores::entry
  # @rbs return: String
  def path_for(id, entry)
    @paths.fetch(id) do
      path = entry.is_a?(Riffer::Rig::Stores::Header) ? new_path(id, entry.cwd) : find(id)
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

  # A session's last update is its file's mtime: appends are the only writes.
  # The store stamps it while it holds the artifact, so the listed header
  # carries it.
  # @rbs path: String
  # @rbs return: ::Riffer::Rig::Stores::Header?
  def header_of(path)
    line = File.foreach(path).first
    hash = parse(line) if line
    return nil unless hash && hash[:type] == Riffer::Rig::Stores::Header::TYPE

    Riffer::Rig::Stores::Header.from_hash(hash, updated: File.mtime(path))
  end

  # @rbs line: String
  # @rbs return: Riffer::Rig::Stores::entry?
  def entry_of(line)
    hash = parse(line)
    return nil unless hash

    ENTRY_TYPES[hash[:type]]&.from_hash(hash)
  end

  # @rbs line: String
  # @rbs return: Hash[Symbol, untyped]?
  def parse(line)
    JSON.parse(line, symbolize_names: true)
  rescue JSON::ParserError
    nil
  end
end
