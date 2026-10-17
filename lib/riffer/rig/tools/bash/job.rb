# frozen_string_literal: true

class Riffer::Rig::Tools::Bash::Job
  # Monotonic Process::CLOCK_MONOTONIC seconds, so elapsed is immune to wall-clock changes.
  # @rbs @id: String
  # @rbs @pid: Integer
  # @rbs @command: String
  # @rbs @output_path: String
  # @rbs @started_at: Float
  # @rbs @ended_at: Float?
  # @rbs @offset: Integer

  # @dynamic id, pid, command, output_path, started_at, offset
  attr_reader :id #: String
  attr_reader :pid #: Integer
  attr_reader :command #: String
  attr_reader :output_path #: String
  attr_reader :started_at #: Float
  attr_reader :offset #: Integer

  # @rbs id: String
  # @rbs pid: Integer
  # @rbs command: String
  # @rbs output_path: String
  # @rbs started_at: Float
  # @rbs ended_at: Float?
  # @rbs offset: Integer
  # @rbs return: void
  def initialize(id:, pid:, command:, output_path:, started_at:, ended_at: nil, offset: 0)
    @id = id
    @pid = pid
    @command = command
    @output_path = output_path
    @started_at = started_at
    @ended_at = ended_at
    @offset = offset
    freeze
  end

  # @rbs return: bool
  def active?
    @ended_at.nil?
  end

  # @rbs return: bool
  def completed?
    !@ended_at.nil?
  end

  # @rbs now: Float
  # @rbs return: Float
  def elapsed(now)
    (@ended_at || now) - @started_at
  end

  # @rbs ended_at: Float
  # @rbs return: Riffer::Rig::Tools::Bash::Job
  def finish(ended_at)
    copy(ended_at: ended_at)
  end

  # @rbs bytes: Integer
  # @rbs return: Riffer::Rig::Tools::Bash::Job
  def advance(bytes)
    copy(offset: offset + bytes)
  end

  private

  # @rbs ended_at: Float?
  # @rbs offset: Integer
  # @rbs return: Riffer::Rig::Tools::Bash::Job
  def copy(ended_at: @ended_at, offset: @offset)
    self.class.new(
      id: id,
      pid: pid,
      command: command,
      output_path: output_path,
      started_at: @started_at,
      ended_at: ended_at,
      offset: offset
    )
  end
end
