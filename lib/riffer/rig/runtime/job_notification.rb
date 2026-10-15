# frozen_string_literal: true

class Riffer::Rig::Runtime::JobNotification < Riffer::Messages::User
  MARKER = :job_notification #: Symbol

  # @dynamic follow_up_exits
  attr_reader :follow_up_exits #: Integer?

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: Riffer::Rig::Runtime::JobNotification
  def self.from_hash(hash)
    new(hash[:content], id: hash[:id], follow_up_exits: hash[:follow_up_exits])
  end

  # @rbs content: String
  # @rbs id: String?
  # @rbs files: Array[Riffer::Messages::User::FilePart]
  # @rbs follow_up_exits: Integer?
  # @rbs return: void
  def initialize(content, id: nil, files: [], follow_up_exits: nil)
    # riffer's User#+ rebuilds a message of the same class with its files.
    super(content, id: id, files: files)
    @follow_up_exits = follow_up_exits
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    super.merge(MARKER => true, follow_up_exits: follow_up_exits).compact
  end
end
