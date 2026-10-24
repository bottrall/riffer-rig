# frozen_string_literal: true

require 'forwardable'

# A real Runtime with its background-job answers scripted over it, for the
# moments a test can't time real jobs to reach.
class OverlaidRuntime
  extend Forwardable

  OVERLAID = %i[running_job_count pending_job_exit_count follow_up run_command].freeze

  def_delegators :@runtime, *(Riffer::Rig::Runtime.public_instance_methods - Object.public_instance_methods - OVERLAID)

  def initialize(runtime, running_job_count: nil, follow_up: nil, before_command: -> {}, after_exit_count: -> {})
    @runtime = runtime
    @running_job_count = running_job_count
    @follow_up = follow_up
    @before_command = before_command
    @after_exit_count = after_exit_count
  end

  def running_job_count
    @running_job_count || @runtime.running_job_count
  end

  def pending_job_exit_count
    @runtime.pending_job_exit_count.tap { @after_exit_count.call }
  end

  def follow_up(&)
    @follow_up ? @follow_up.call(&) : @runtime.follow_up(&)
  end

  def run_command(*, &)
    @before_command.call
    @runtime.run_command(*, &)
  end
end
