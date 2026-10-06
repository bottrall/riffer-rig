# frozen_string_literal: true

class Riffer::Rig::Stores::Header
  TYPE = 'header' #: String

  include Riffer::Rig::Support::Equatable

  # @rbs @schema_version: Integer
  # @rbs @id: String
  # @rbs @cwd: String
  # @rbs @created_at: String
  # @rbs @model: String
  # @rbs @riffer_rig_version: String
  # @rbs @riffer_version: String
  # @rbs @title: String
  # @rbs @updated: Time?

  # @dynamic schema_version, id, cwd, created_at, model, riffer_rig_version, riffer_version, title, updated
  attr_reader :schema_version #: Integer
  attr_reader :id #: String
  attr_reader :cwd #: String
  attr_reader :created_at #: String
  attr_reader :model #: String
  attr_reader :riffer_rig_version #: String
  attr_reader :riffer_version #: String
  attr_reader :title #: String
  # Store-derived metadata, not entry data: stamped by the store while it
  # holds the physical artifact (the JSONL file's mtime), so it is excluded
  # from to_h.
  attr_reader :updated #: Time?

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs updated: Time?
  # @rbs return: ::Riffer::Rig::Stores::Header?
  def self.from_hash(hash, updated: nil)
    schema_version = hash[:schema_version]
    id = hash[:id]
    cwd = hash[:cwd]
    created_at = hash[:created_at]
    model = hash[:model]
    riffer_rig_version = hash[:riffer_rig_version]
    riffer_version = hash[:riffer_version]
    title = hash[:title]
    return nil unless schema_version.is_a?(Integer)
    return nil unless [id, cwd, created_at, model, riffer_rig_version, riffer_version, title].all?(String)

    new(
      schema_version: schema_version,
      id: id,
      cwd: cwd,
      created_at: created_at,
      model: model,
      riffer_rig_version: riffer_rig_version,
      riffer_version: riffer_version,
      title: title,
      updated: updated
    )
  end

  # @rbs schema_version: Integer
  # @rbs id: String
  # @rbs cwd: String
  # @rbs created_at: String
  # @rbs model: String
  # @rbs riffer_rig_version: String
  # @rbs riffer_version: String
  # @rbs title: String
  # @rbs updated: Time?
  # @rbs return: void
  def initialize(
    schema_version:,
    id:,
    cwd:,
    created_at:,
    model:,
    riffer_rig_version:,
    riffer_version:,
    title:,
    updated: nil
  )
    @schema_version = schema_version
    @id = id
    @cwd = cwd
    @created_at = created_at
    @model = model
    @riffer_rig_version = riffer_rig_version
    @riffer_version = riffer_version
    @title = title
    @updated = updated
    freeze
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    {
      type: TYPE,
      schema_version: @schema_version,
      id: @id,
      cwd: @cwd,
      created_at: @created_at,
      model: @model,
      riffer_rig_version: @riffer_rig_version,
      riffer_version: @riffer_version,
      title: @title
    }
  end
end
