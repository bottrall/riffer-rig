# frozen_string_literal: true

class Riffer::Rig::Events::JobExit
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :job_exit, :job_id, :command, :exit_status, :duration, :output_path

  # @dynamic job_id, command, exit_status, duration, output_path
  attr_reader :job_id #: String
  attr_reader :command #: String
  attr_reader :exit_status #: Integer
  attr_reader :duration #: Float
  attr_reader :output_path #: String

  # @rbs completion: Riffer::Rig::Runtime::JobCompletion
  # @rbs return: void
  def initialize(completion)
    @job_id = completion.job_id
    @command = completion.command
    @exit_status = completion.exit_status
    @duration = completion.duration
    @output_path = completion.output_path
    freeze
  end
end
