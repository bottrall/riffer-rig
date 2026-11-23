# frozen_string_literal: true

class Riffer::Rig::Runtime::Snapshot
  include Riffer::Rig::Support::Equatable

  # @dynamic id, messages, model, reasoning, skills, baseline
  attr_reader :id #: String
  attr_reader :messages #: Array[Riffer::Messages::Base]
  attr_reader :model #: String?
  attr_reader :reasoning #: String?
  attr_reader :skills #: Array[String]
  attr_reader :baseline #: Riffer::Rig::Runtime::Baseline?

  # @rbs snapshot: Riffer::Rig::Runtime::Snapshot | Hash[Symbol, untyped]
  # @rbs return: Riffer::Rig::Runtime::Snapshot
  def self.of(snapshot)
    snapshot.is_a?(Riffer::Rig::Runtime::Snapshot) ? snapshot : from_h(snapshot)
  end

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: Riffer::Rig::Runtime::Snapshot
  def self.from_h(hash)
    baseline = hash[:baseline] && Riffer::Rig::Runtime::Baseline.from_h(hash[:baseline])
    new(
      id: hash.fetch(:id),
      # Upstream candidate: riffer's Serializer carries an agent's config, never
      # its history, so this and to_h round-trip the session message by message;
      # a Session.from_h could also heal orphaned tool calls on load.
      # Without the baseline it was signed under, reasoning can't be replayed.
      messages: hash.fetch(:messages).map { |stored| message(baseline ? stored : stored.except(:reasoning)) },
      model: hash.fetch(:model),
      reasoning: hash[:reasoning].is_a?(String) ? hash[:reasoning] : nil,
      skills: hash.fetch(:skills),
      baseline: baseline
    )
  end

  # @rbs hash: Hash[Symbol, untyped]
  # @rbs return: Riffer::Messages::Base
  def self.message(hash)
    # riffer rebuilds a message from its role alone, which would bring a job
    # notification back as typed input.
    return Riffer::Rig::Runtime::JobNotification.from_hash(hash) if hash[Riffer::Rig::Runtime::JobNotification::MARKER]
    return Riffer::Rig::Runtime::ContextUpdate.from_hash(hash) if hash[Riffer::Rig::Runtime::ContextUpdate::MARKER]

    Riffer::Messages::Base.from_hash(hash)
  end

  # @rbs id: String
  # @rbs messages: Array[Riffer::Messages::Base]
  # @rbs model: String?
  # @rbs reasoning: String?
  # @rbs skills: Array[String]
  # @rbs baseline: Riffer::Rig::Runtime::Baseline?
  # @rbs return: void
  def initialize(id:, messages:, model:, skills:, reasoning: nil, baseline: nil)
    @id = id
    @messages = messages
    @model = model
    @reasoning = reasoning
    @skills = skills
    @baseline = baseline
    freeze
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    {
      id: @id,
      messages: @messages.map(&:to_h),
      model: @model,
      reasoning: @reasoning,
      skills: @skills,
      baseline: @baseline&.to_h
    }
  end

  # @rbs return: Riffer::Rig::Runtime::Snapshot
  def without_model
    self.class.new(
      id: @id,
      messages: @messages,
      model: nil,
      reasoning: @reasoning,
      skills: @skills,
      baseline: @baseline
    )
  end

  # @rbs return: Riffer::Rig::Runtime::Snapshot
  def without_reasoning
    self.class.new(id: @id, messages: @messages, model: @model, reasoning: nil, skills: @skills, baseline: @baseline)
  end

  # @rbs return: Riffer::Agent::Session
  def session
    baseline = @baseline
    # riffer's Session appends to the array it is given.
    session = Riffer::Agent::Session.new(messages: baseline ? baseline.head(@messages) : @messages.dup)
    session.discard_pending_tool_calls
    session
  end

  # @rbs return: Riffer::Providers::TokenUsage?
  def usage
    # Upstream candidate: a loaded session could restore its own tally.
    Riffer::Rig::Runtime::Usage.sum(@messages)
  end

  # @rbs credentials: Hash[Symbol, Hash[Symbol, String]]
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs fallback: String
  # @rbs return: String?
  def restorable_model(credentials, host, fallback)
    saved = @model
    return nil unless saved

    provider = saved.split('/', 2).first.to_s
    return saved if credentials.key?(provider.to_sym)

    host.notify("Not restoring model #{saved}: #{provider} has no credentials; using #{fallback}", level: :warning)
    nil
  end
end
