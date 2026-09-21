# frozen_string_literal: true

class Riffer::Rig::Runtime::CancelFlag
  # @rbs @mutex: Thread::Mutex
  # @rbs @set: bool

  # @rbs return: void
  def initialize
    @mutex = Mutex.new
    @set = false
  end

  # @rbs return: void
  def set
    @mutex.synchronize { @set = true }
  end

  # @rbs return: void
  def clear
    @mutex.synchronize { @set = false }
  end

  # @rbs return: bool
  def set?
    @mutex.synchronize { @set }
  end
end
