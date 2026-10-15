# frozen_string_literal: true

class Riffer::Rig::Runtime::JobInbox
  # @rbs @mutex: Thread::Mutex
  # @rbs @arrived: Thread::ConditionVariable
  # @rbs @clock: ^() -> Float
  # @rbs @pending: Array[Riffer::Rig::Runtime::JobCompletion]
  # @rbs @subscribers: Array[^(Riffer::Rig::Runtime::JobCompletion) -> void]
  # @rbs @closed: bool

  # @rbs clock: ^() -> Float
  # @rbs return: void
  def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @mutex = Mutex.new
    @arrived = ConditionVariable.new
    @clock = clock
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
      @arrived.broadcast
      @subscribers.each { |subscriber| subscriber.call(completion) }
    end
  end

  # @rbs return: Array[Riffer::Rig::Runtime::JobCompletion]
  def drain
    @mutex.synchronize { @pending.shift(@pending.size) }
  end

  # @rbs timeout: Numeric?
  # @rbs return: bool
  def await(timeout)
    deadline = timeout && (@clock.call + timeout)
    @mutex.synchronize do
      until @pending.any? || @closed
        remaining = deadline && (deadline - @clock.call)
        break if remaining && !remaining.positive?

        @arrived.wait(@mutex, remaining)
      end
      @pending.any?
    end
  end

  # @rbs return: void
  def close
    @mutex.synchronize do
      @closed = true
      @arrived.broadcast
    end
  end
end
