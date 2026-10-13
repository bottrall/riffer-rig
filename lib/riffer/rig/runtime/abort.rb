# frozen_string_literal: true

class Riffer::Rig::Runtime::Abort
  class Signal < Exception; end # rubocop:disable Lint/InheritException, Rig/NoInheritance -- provider SDKs rescue a StandardError around the request and retry it

  # Rig's own callbacks (hooks, tools, stores, the host) run under this, so the
  # signal never cuts one off halfway.
  SHIELD = { Signal => :never }.freeze #: Hash[singleton(Exception), Symbol]

  # @rbs @mutex: Thread::Mutex
  # @rbs @thread: Thread?

  # @rbs return: void
  def initialize
    @mutex = Mutex.new
    @thread = nil
  end

  # @rbs &: () -> Riffer::Agent::Response
  # @rbs return: Riffer::Agent::Response?
  def window(&)
    Thread.handle_interrupt(SHIELD) do
      arm(Thread.current)
      begin
        # Only at a blocking call, so the bookkeeping riffer does between two
        # callbacks (recording a batch of tool results) is never split.
        Thread.handle_interrupt(Signal => :on_blocking, &)
      rescue Signal
        nil
      ensure
        arm(nil)
        discard_pending
      end
    end
  end

  # @rbs return: void
  def fire
    @mutex.synchronize do
      # Upstream candidate: a cancel token on riffer's run loop. A turn waiting
      # on the provider is blocked in an HTTP read that runs no rig code, so
      # only an exception raised into its thread can wake it.
      @thread&.raise(Signal)
      # One signal a window, which is all #discard_pending can clear.
      @thread = nil
    end
  end

  private

  # @rbs thread: Thread?
  # @rbs return: void
  def arm(thread)
    @mutex.synchronize { @thread = thread }
  end

  # A signal that never reached a blocking call would otherwise be raised in
  # the caller, after the turn it was meant for.
  # @rbs return: void
  def discard_pending
    Thread.handle_interrupt(Signal => :immediate) { Thread.pass }
  rescue Signal
    nil
  end
end
