# frozen_string_literal: true

class Riffer::Rig::Terminal::Repl
  # @rbs @console: Riffer::Rig::Terminal::Console
  # @rbs @frame: Riffer::Rig::Terminal::Frame
  # @rbs @keys: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs @asks: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs @prompter: Riffer::Rig::Terminal::FramePrompter
  # @rbs @peek: Riffer::Rig::Terminal::Peek
  # @rbs @interrupt: ^() -> void
  # @rbs @reader: Thread?
  # @rbs @runtime: Riffer::Rig::Runtime?
  # @rbs @completion: Riffer::Rig::Terminal::Autocomplete
  # @rbs @queue: Riffer::Rig::Terminal::MessageQueue
  # @rbs @asking: bool
  # @rbs @armed: bool
  # @rbs @woken: bool
  # @rbs @busy: bool
  # @rbs @closed: bool
  # @rbs @mutex: Mutex
  # @rbs @arrival: ConditionVariable

  # @rbs console: Riffer::Rig::Terminal::Console
  # @rbs frame: Riffer::Rig::Terminal::Frame
  # @rbs keys: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs asks: Thread::Queue[Riffer::Rig::Terminal::Key]
  # @rbs prompter: Riffer::Rig::Terminal::FramePrompter
  # @rbs peek: Riffer::Rig::Terminal::Peek
  # @rbs interrupt: ^() -> void
  # @rbs return: void
  def initialize(console:, frame:, keys:, asks:, prompter:, peek:, interrupt:)
    @console = console
    @frame = frame
    @keys = keys
    @asks = asks
    @prompter = prompter
    @peek = peek
    @interrupt = interrupt
    @reader = nil
    @runtime = nil
    @completion = Riffer::Rig::Terminal::Autocomplete.new(commands: [])
    @queue = Riffer::Rig::Terminal::MessageQueue.new
    @asking = false
    @armed = false
    @woken = false
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
    @mutex.synchronize { @runtime = runtime }
    runtime.on_job_exit { wake }
  end

  # @rbs recorded: Array[Riffer::Rig::Terminal::Replay::_Recorded]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: void
  def replay(recorded, theme:)
    width = @frame.measure&.last
    @console.print(Riffer::Rig::Terminal::Replay.call(recorded, theme: theme, width: width))
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
    @prompter.ask(question, options: options, secret: secret)
  ensure
    @mutex.synchronize do
      @asking = false
      # A key typed behind the answer reached the ask before it returned.
      Array.new(@asks.size) { @asks.pop }.compact.each { |key| press(key) }
      @frame.complete(@completion)
    end
  end

  # @rbs &block: (String | :job_exit) -> void
  # @rbs return: void
  def run
    while (entry = take)
      yield entry
    end
  end

  private

  # @rbs return: (String | :job_exit)?
  def take
    @mutex.synchronize do
      @busy = false
      @arrival.wait(@mutex) while @queue.messages.empty? && !@woken && !@closed
      message, @queue = @queue.dequeue
      entry = message ? message.text : job_exit
      @busy = !entry.nil?
      @frame.queued(@queue.messages.size)
      entry
    end
  rescue Interrupt
    retry if arm
  end

  # @rbs return: :job_exit | nil
  def job_exit
    return unless @woken && !@closed

    # Exits that land while a turn runs, or together, are one wake-up: the
    # turn it starts takes every exit the Runtime holds by then.
    @woken = false
    disarm
    :job_exit
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
        @peek.press(key)
        @mutex.synchronize { @asking ? @asks << key : press(key) }
      end
    end
  ensure
    # An ask in flight, and any later one, reads this as the end of input.
    @asks.close
    @mutex.synchronize { close }
  end

  # @rbs return: void
  def wake
    @mutex.synchronize do
      @woken = true
      @arrival.signal
    end
  end

  # @rbs key: Riffer::Rig::Terminal::Key
  # @rbs return: void
  def press(key)
    disarm
    @completion = edit(key)
    @frame.complete(@completion)
  end

  # @rbs return: void
  def disarm
    @frame.status('') if @armed
    @armed = false
  end

  # @rbs key: Riffer::Rig::Terminal::Key
  # @rbs return: Riffer::Rig::Terminal::Autocomplete
  def edit(key)
    text = @completion.editor.text
    case key.name
    when :enter
      enqueue(text)
      @completion.submit
    when :ctrl_d
      close if text.empty?
      @completion
    else
      # A /reload, /new or /resume changes the commands between keys.
      @completion.over(@runtime&.commands || []).press(key)
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
