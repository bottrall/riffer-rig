# frozen_string_literal: true

class Riffer::Rig::Terminal::Repl
  # @rbs @console: Riffer::Rig::Terminal::Console
  # @rbs @frame: Riffer::Rig::Terminal::Frame
  # @rbs @keys: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs @asks: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs @prompter: Riffer::Rig::Terminal::FramePrompter
  # @rbs @jobs: Riffer::Rig::Terminal::JobCounter
  # @rbs @interrupt: ^() -> void
  # @rbs @reader: Thread?
  # @rbs @editor: Riffer::Rig::Terminal::LineEditor
  # @rbs @queue: Riffer::Rig::Terminal::MessageQueue
  # @rbs @asking: bool
  # @rbs @armed: bool
  # @rbs @busy: bool
  # @rbs @closed: bool
  # @rbs @mutex: Mutex
  # @rbs @arrival: ConditionVariable

  # @rbs console: Riffer::Rig::Terminal::Console
  # @rbs frame: Riffer::Rig::Terminal::Frame
  # @rbs keys: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs asks: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs prompter: Riffer::Rig::Terminal::FramePrompter
  # @rbs jobs: Riffer::Rig::Terminal::JobCounter
  # @rbs interrupt: ^() -> void
  # @rbs return: void
  def initialize(console:, frame:, keys:, asks:, prompter:, jobs:, interrupt:)
    @console = console
    @frame = frame
    @keys = keys
    @asks = asks
    @prompter = prompter
    @jobs = jobs
    @interrupt = interrupt
    @reader = nil
    @editor = Riffer::Rig::Terminal::LineEditor.new
    @queue = Riffer::Rig::Terminal::MessageQueue.new
    @asking = false
    @armed = false
    @busy = false
    @closed = false
    @mutex = Mutex.new
    @arrival = ConditionVariable.new
  end

  # @rbs return: void
  def start
    @console.start
    # Turns and asks stay on the calling thread, where the Interrupt of a
    # Ctrl-C is raised, so the keys are read on one of their own.
    @reader = Thread.new { read }
  end

  # @rbs return: void
  def stop
    @reader&.kill
    @reader&.join
    @console.stop
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def watch(runtime)
    @jobs.watch(runtime)
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question, options:, secret:)
    @mutex.synchronize do
      @asking = true
      @frame.input(Riffer::Rig::Terminal::LineEditor.new)
    end
    # The prompter appends straight to the frame, which would put the
    # question above a line the console still holds.
    @console.settle
    @prompter.ask(question, options: options, secret: secret)
  ensure
    @mutex.synchronize do
      @asking = false
      # A key typed behind the answer reached the ask before it returned.
      Array.new(@asks.size) { @asks.pop }.compact.each { |key| press(key) }
      @frame.input(@editor)
    end
  end

  # @rbs &block: (String) -> void
  # @rbs return: void
  def run
    while (message = take)
      yield message.text
      @console.settle
    end
  end

  private

  # @rbs return: Riffer::Rig::Terminal::MessageQueue::Message?
  def take
    @mutex.synchronize do
      @busy = false
      @arrival.wait(@mutex) while @queue.messages.empty? && !@closed
      message, @queue = @queue.dequeue
      @busy = !message.nil?
      @frame.queued(@queue.messages.size)
      message
    end
  rescue Interrupt
    retry if arm
  end

  # @rbs return: bool
  def arm
    @mutex.synchronize do
      return false if @armed

      @armed = true
      @frame.status(Riffer::Rig::Terminal::EXIT_HINT)
      true
    end
  end

  # @rbs return: void
  def read
    while (key = @keys.pop)
      if key.name == :ctrl_c
        # Raw mode delivers Ctrl-C as a key. Sent on as the signal it stands
        # for, it lands where a blocking terminal's does: on the trap of a
        # running turn, or as the Interrupt of a prompt.
        @interrupt.call
      else
        # One reader hands each key to the ask in flight or to the line, so
        # the two never race for it.
        @mutex.synchronize { @asking ? @asks << key : press(key) }
      end
    end
  ensure
    # An ask in flight, and any later one, reads this as the end of input.
    @asks.close
    @mutex.synchronize { close }
  end

  # @rbs key: Riffer::Rig::Terminal::Key
  # @rbs return: void
  def press(key)
    @frame.status('') if @armed
    @armed = false
    @editor = edit(key)
    @frame.input(@editor)
  end

  # @rbs key: Riffer::Rig::Terminal::Key
  # @rbs return: Riffer::Rig::Terminal::LineEditor
  def edit(key)
    case key.name
    when :enter
      enqueue(@editor.text)
      @editor.submit
    when :ctrl_d
      close if @editor.text.empty?
      @editor
    else
      @editor.press(key)
    end
  end

  # @rbs line: String
  # @rbs return: void
  def enqueue(line)
    @queue = @queue.enqueue(line)
    # An idle loop takes the message at once, and a count drawn for that
    # instant would only flicker.
    @frame.queued(@queue.messages.size) if @busy
    @arrival.signal
  end

  # @rbs return: void
  def close
    # Only the drain ends here: what is already queued still runs, and the
    # keys are read until it has, so those turns stay interruptible.
    @closed = true
    @arrival.signal
  end
end
