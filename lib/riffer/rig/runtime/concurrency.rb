# frozen_string_literal: true

class Riffer::Rig::Runtime::Concurrency
  # @rbs @busy: bool
  # @rbs @closed: bool
  # @rbs @depth: Integer
  # @rbs @thread: Thread?

  # @rbs return: void
  def initialize
    @busy = false
    @closed = false
    @depth = 0
    @thread = nil
  end

  # @rbs return: void
  def claim
    raise Riffer::Rig::Runtime::BusyError, 'a prompt is already running on this Runtime' if @busy
    raise Riffer::Rig::Runtime::ClosedError, 'this Runtime is closed' if @closed

    hold
  end

  # Rebuild is a configuration swap at a quiet boundary, not a turn entry, so
  # it may run nested under the thread that holds the Runtime — the /reload
  # command and the automatic reload check both do. Another thread is still
  # refused while work runs.
  # @rbs return: void
  def claim_rebuild
    if @busy && @thread != Thread.current
      raise Riffer::Rig::Runtime::BusyError, 'a prompt is already running on this Runtime'
    end
    raise Riffer::Rig::Runtime::ClosedError, 'this Runtime is closed' if @closed

    hold
  end

  # @rbs return: void
  def release
    @depth -= 1
    return if @depth.positive?

    @busy = false
    @thread = nil
  end

  # @rbs return: void
  def close
    @closed = true
  end

  # @rbs return: bool
  def closed?
    @closed
  end

  private

  # @rbs return: void
  def hold
    @busy = true
    @depth += 1
    @thread = Thread.current
  end
end
