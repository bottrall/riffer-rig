# frozen_string_literal: true

class Riffer::Rig::Runtime::JobInbox
  # @rbs @mutex: Thread::Mutex
  # @rbs @pending: Array[Riffer::Rig::Runtime::JobCompletion]
  # @rbs @subscribers: Array[^(Riffer::Rig::Runtime::JobCompletion) -> void]
  # @rbs @closed: bool

  # @rbs return: void
  def initialize
    @mutex = Mutex.new
    @pending = []
    @subscribers = []
    @closed = false
  end

  # @rbs &block: (Riffer::Rig::Runtime::JobCompletion) -> void
  # @rbs return: void
  def subscribe(&block)
    @mutex.synchronize { @subscribers << block }
  end

  # @rbs completion: Riffer::Rig::Runtime::JobCompletion
  # @rbs return: void
  def push(completion)
    # Subscribers run under the lock so that once close returns, none is
    # running and none will start.
    @mutex.synchronize do
      return if @closed

      @pending << completion
      @subscribers.each { |subscriber| subscriber.call(completion) }
    end
  end

  # @rbs return: Array[Riffer::Rig::Runtime::JobCompletion]
  def drain
    @mutex.synchronize { @pending.shift(@pending.size) }
  end

  # @rbs return: void
  def close
    @mutex.synchronize { @closed = true }
  end
end
