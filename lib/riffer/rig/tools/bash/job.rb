# frozen_string_literal: true

class Riffer::Rig::Tools::Bash::Job
  # Monotonic Process::CLOCK_MONOTONIC seconds, so elapsed is immune to wall-clock changes.
  # @rbs @id: String
  # @rbs @pid: Integer
  # @rbs @output_path: String
  # @rbs @started_at: Float
  # @rbs @status: Integer?
  # @rbs @ended_at: Float?

  # @dynamic id, pid, output_path, started_at, status
  attr_reader :id #: String
  attr_reader :pid #: Integer
  attr_reader :output_path #: String
  attr_reader :started_at #: Float
  attr_reader :status #: Integer?

  # @rbs id: String
  # @rbs pid: Integer
  # @rbs output_path: String
  # @rbs started_at: Float
  # @rbs status: Integer?
  # @rbs ended_at: Float?
  # @rbs return: void
  def initialize(id:, pid:, output_path:, started_at:, status: nil, ended_at: nil)
    @id = id
    @pid = pid
    @output_path = output_path
    @started_at = started_at
    @status = status
    @ended_at = ended_at
    freeze
  end

  # @rbs return: bool
  def active?
    status.nil?
  end

  # @rbs return: bool
  def completed?
    !status.nil?
  end

  # @rbs now: Float
  # @rbs return: Float
  def elapsed(now)
    (@ended_at || now) - @started_at
  end

  # @rbs status: Integer
  # @rbs ended_at: Float
  # @rbs return: Riffer::Rig::Tools::Bash::Job
  def finish(status, ended_at)
    self.class.new(
      id: id,
      pid: pid,
      output_path: output_path,
      started_at: @started_at,
      status: status,
      ended_at: ended_at
    )
  end
end
