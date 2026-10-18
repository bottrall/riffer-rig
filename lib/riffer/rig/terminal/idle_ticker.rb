# frozen_string_literal: true

class Riffer::Rig::Terminal::IdleTicker
  TICK_SECONDS = 1.0 #: Float

  # @rbs @footer: Riffer::Rig::Terminal::Frame
  # @rbs @halt: Thread::Queue[true]
  # @rbs @thread: Thread?

  # @rbs footer: Riffer::Rig::Terminal::Frame
  # @rbs return: void
  def initialize(footer:)
    @footer = footer
    @halt = Queue.new
    @thread = nil
  end

  # @rbs return: void
  def start
    @thread = Thread.new { @footer.idle_tick until @halt.pop(timeout: TICK_SECONDS) }
  end

  # @rbs return: void
  def stop
    @halt << true
    @thread&.join
  end
end
