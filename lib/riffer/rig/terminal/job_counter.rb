# frozen_string_literal: true

class Riffer::Rig::Terminal::JobCounter
  # @rbs @footer: Riffer::Rig::Terminal::Frame
  # @rbs @mutex: Mutex

  # @rbs footer: Riffer::Rig::Terminal::Frame
  # @rbs return: void
  def initialize(footer:)
    @footer = footer
    @mutex = Mutex.new
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def watch(runtime)
    # Nothing announces a job starting; the tool result of the call that
    # started it is the first message recorded after it.
    runtime.on_message { refresh(runtime) }
    runtime.on_job_exit { refresh(runtime) }
    refresh(runtime)
  end

  private

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def refresh(runtime)
    # A job exits on its own thread: without the lock, a count read before
    # the exit could be drawn over the one read after it.
    @mutex.synchronize { @footer.jobs(runtime.running_job_count) }
  end
end
