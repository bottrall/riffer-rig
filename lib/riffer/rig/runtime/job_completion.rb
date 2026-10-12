# frozen_string_literal: true

class Riffer::Rig::Runtime::JobCompletion
  # @dynamic job_id, command, exit_status, duration, output_path, tail
  attr_reader :job_id #: String
  attr_reader :command #: String
  attr_reader :exit_status #: Integer
  attr_reader :duration #: Float
  attr_reader :output_path #: String
  attr_reader :tail #: String

  # @rbs job_id: String
  # @rbs command: String
  # @rbs exit_status: Integer
  # @rbs duration: Float
  # @rbs output_path: String
  # @rbs tail: String
  # @rbs return: void
  def initialize(job_id:, command:, exit_status:, duration:, output_path:, tail:)
    @job_id = job_id
    @command = command
    @exit_status = exit_status
    @duration = duration
    @output_path = output_path
    @tail = tail
    freeze
  end
end
