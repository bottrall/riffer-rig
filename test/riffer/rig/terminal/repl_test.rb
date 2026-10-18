# frozen_string_literal: true

require 'test_helper'

class RecordingConsole
  def initialize(log) = @log = log

  def start = @log << :start

  def stop = @log << :stop

  def print(*chunks) = @log << [:print, chunks.join]
end

class LoggingFrame
  attr_reader :lines, :palettes, :statuses, :counts
  attr_writer :size

  def initialize(log)
    @log = log
    @lines = []
    @palettes = []
    @statuses = []
    @counts = []
    @size = [24, 80]
  end

  def measure = @size

  def input(editor)
    @lines << editor.text
    @log << [:input, editor.text]
  end

  def complete(completion)
    @palettes << completion.matches.map(&:name)
    input(completion.editor)
  end

  def status(status)
    @statuses << status
    @log << [:status, status]
  end

  def queued(count)
    @counts << count
    @log << [:queued, count]
  end
end

class QueuePrompter
  def initialize(asks, log)
    @asks = asks
    @log = log
    @behind = 0
  end

  def hold_for(behind) = @behind = behind

  def ask(question, options:, secret:)
    @log << [:asked, question, options, secret]
    answer = +''
    loop do
      key = @asks.pop
      return nil if key.nil?

      if key.name == :ctrl_c
        @log << [:interrupted, question]
        raise Interrupt
      end
      break if key.name == :enter

      answer << key.text.to_s
    end
    sleep 0.001 until @asks.size >= @behind
    answer
  end
end

class WatchedRuntime
  attr_reader :commands

  def initialize(*names)
    @subscribers = []
    reload(*names)
  end

  def reload(*names)
    @commands = names.map { |name| Riffer::Rig::Command.new(name, description: name, extension: :test) { nil } }
  end

  def on_job_exit(&block) = @subscribers << block

  def exit_job = @subscribers.each(&:call)
end

class RecordingPeek
  attr_reader :pressed

  def initialize = @pressed = Queue.new

  def press(key) = @pressed << key.name
end

describe Riffer::Rig::Terminal::Repl do
  def setup
    @log = Queue.new
    @keys = Queue.new
    @asks = Queue.new
    @frame = LoggingFrame.new(@log)
    @prompter = QueuePrompter.new(@asks, @log)
    @peek = RecordingPeek.new
    @interrupts = Queue.new
  end

  def timeout_seconds = 5

  def repl(interrupt: -> { @interrupts << :interrupt }, builtins: [])
    @repl ||= Riffer::Rig::Terminal::Repl.new(
      console: RecordingConsole.new(@log),
      frame: @frame,
      keys: @keys,
      asks: @asks,
      prompter: @prompter,
      peek: @peek,
      interrupt: interrupt,
      builtins: builtins
    )
  end

  # Stands in for the signal: Ruby raises it in the thread once it blocks.
  def signalling
    repl(
      interrupt: lambda do
        sleep 0.001 until @session.status == 'sleep'
        @session.raise(Interrupt)
      end
    )
  end

  def begin_session(&turn)
    @turns = []
    @session = Thread.new do
      repl.start
      begin
        repl.run do |line|
          @turns << line
          turn&.call(line)
        end
      ensure
        repl.stop
      end
    end
    @session.report_on_exception = false
  end

  def finish
    @session.join(timeout_seconds) || raise("the session was still open after #{timeout_seconds}s")
    @turns
  end

  def session(&)
    begin_session(&)
    finish
  end

  def type(text)
    text.each_char do |char|
      @keys << (char == "\r" ? Riffer::Rig::Terminal::Key.new(:enter) : Riffer::Rig::Terminal::Key.new(:text, char))
    end
  end

  def press(*names)
    names.each { |name| @keys << Riffer::Rig::Terminal::Key.new(name) }
  end

  def await(event)
    loop do
      seen = @log.pop(timeout: timeout_seconds) || raise("no #{event.inspect} within #{timeout_seconds}s")
      break if seen == event
    end
  end

  def logged
    Array.new(@log.size) { @log.pop }
  end

  def hint = Riffer::Rig::Terminal::EXIT_HINT

  describe '#start' do
    it 'starts the console' do
      @keys.close

      session

      assert_equal :start, logged.first
    end
  end

  describe '#stop' do
    it 'reads no key once it has stopped' do
      press(:ctrl_d)
      session

      type('a')

      assert_equal 1, @keys.size
    end

    it 'stops the console' do
      @keys.close

      session

      assert_equal :stop, logged.last
    end
  end

  describe '#watch' do
    it 'runs a job exit from the Runtime as a turn' do
      runtime = WatchedRuntime.new
      repl.watch(runtime)
      begin_session { @keys.close }
      runtime.exit_job

      assert_equal [:job_exit], finish
    end

    it 'completes from the commands of the Runtime watched last' do
      repl.watch(WatchedRuntime.new('auth'))
      repl.watch(WatchedRuntime.new('model'))
      type('/')
      @keys.close

      session

      assert_equal [%w[model]], @frame.palettes
    end

    it 'completes the built-in commands alongside those of the Runtime' do
      repl(builtins: [Riffer::Rig::Terminal::Builtin.new('resume', description: 'Pick a session')])
      repl.watch(WatchedRuntime.new('reload'))
      type('/re')
      @keys.close

      session

      assert_equal %w[reload resume], @frame.palettes.last
    end
  end

  describe '#replay' do
    def recorded
      [
        Riffer::Rig::Stores::MessageEntry.new(
          message: { role: 'user', content: 'Go' },
          recorded_at: '2026-10-11T00:00:00.000Z'
        ),
        Riffer::Rig::Stores::MessageEntry.new(
          message: { role: 'assistant', content: 'The picker now reads its rows.' },
          recorded_at: '2026-10-11T00:00:41.000Z'
        )
      ]
    end

    def theme(color: false)
      Riffer::Rig::Terminal::Theme.new(enabled: color)
    end

    def rendered(theme, width)
      [[:print, Riffer::Rig::Terminal::Replay.call(recorded, theme: theme, width: width)]]
    end

    it 'prints the recorded turns to the console at the width of the terminal' do
      @frame.size = [24, 24]
      repl.replay(recorded, theme: theme)

      assert_equal rendered(theme, 24), logged
    end

    it 'prints them unwrapped on a terminal that reports no size' do
      @frame.size = nil
      repl.replay(recorded, theme: theme)

      assert_equal rendered(theme, nil), logged
    end

    it 'paints them in the theme' do
      repl.replay(recorded, theme: theme(color: true))

      assert_equal rendered(theme(color: true), 80), logged
    end
  end

  describe '#ask' do
    it 'clears a draft from the footer for the ask' do
      drafted = Queue.new
      type("one\rdr")
      begin_session do
        drafted.pop
        repl.ask('who?', options: nil, secret: false)
      end
      await([:input, 'dr'])
      drafted << true
      await([:asked, 'who?', nil, false])
      @keys.close
      finish

      assert_equal ['dr', ''], @frame.lines[-3, 2]
    end

    it 'passes the question, options and secrecy to the prompter' do
      type("one\r")
      @keys.close

      session { repl.ask('key?', options: %w[a b], secret: true) }

      assert_includes logged, [:asked, 'key?', %w[a b], true]
    end

    it 'hands the keys typed during the ask to the prompter' do
      answer = nil
      type("one\r")
      begin_session { answer = repl.ask('who?', options: nil, secret: false) }
      await([:asked, 'who?', nil, false])
      type("jake\r")
      @keys.close
      finish

      assert_equal 'jake', answer
    end

    it 'keeps the keys typed during the ask off the input line' do
      type("one\r")
      begin_session { repl.ask('who?', options: nil, secret: false) }
      await([:asked, 'who?', nil, false])
      type("jake\r")
      @keys.close
      finish

      refute_includes @frame.lines, 'j'
    end

    it 'returns the keys typed behind the answer to the input line' do
      @prompter.hold_for(2)
      type("one\r")
      begin_session { repl.ask('who?', options: nil, secret: false) }
      await([:asked, 'who?', nil, false])
      type("y\rab")
      @keys.close
      finish

      assert_equal 'ab', @frame.lines.last
    end

    it 'redraws the draft once the ask has answered' do
      drafted = Queue.new
      type("one\rdr")
      begin_session do
        drafted.pop
        repl.ask('who?', options: nil, secret: false)
      end
      await([:input, 'dr'])
      drafted << true
      await([:asked, 'who?', nil, false])
      type("jake\r")
      @keys.close
      finish

      assert_equal 'dr', @frame.lines.last
    end

    describe 'when Ctrl-C interrupts it' do
      def interrupt_ask
        answer = :unanswered
        type("one\r")
        begin_session { answer = repl.ask('who?', options: nil, secret: false) }
        await([:asked, 'who?', nil, false])
        press(:ctrl_c)
        await([:interrupted, 'who?'])
        @keys.close
        finish
        answer
      end

      it 'answers nothing' do
        assert_nil interrupt_ask
      end

      it 'sends the Ctrl-C on as an interrupt once' do
        interrupt_ask

        assert_equal 1, @interrupts.size
      end

      it 'sends the interrupt from the thread that asked' do
        senders = []
        repl(interrupt: -> { senders << Thread.current })
        interrupt_ask

        assert_equal [@session], senders
      end

      it 'raises the Interrupt of a signal no turn traps' do
        repl(interrupt: -> { raise Interrupt })
        interrupted = false
        type("one\r")
        begin_session do
          repl.ask('who?', options: nil, secret: false)
        rescue Interrupt
          interrupted = true
        end
        await([:asked, 'who?', nil, false])
        press(:ctrl_c)
        @keys.close
        finish

        assert interrupted
      end
    end

    it 'takes the keys back when the ask is interrupted' do
      type("one\r")
      begin_session { repl.ask('who?', options: nil, secret: false) }
      await([:asked, 'who?', nil, false])
      press(:ctrl_c)
      type('x')
      @keys.close
      finish

      assert_equal 'x', @frame.lines.last
    end
  end

  describe '#run' do
    it 'runs a submitted line as a turn' do
      type("one\r")
      @keys.close

      assert_equal ['one'], session
    end

    it 'runs the lines submitted during a turn back to back in order' do
      type("one\r")

      turns = session do |line|
        next unless line == 'one'

        type("two\rthree\r")
        @keys.close
        await([:queued, 2])
      end

      assert_equal %w[one two three], turns
    end

    it 'runs a line submitted before the loop began' do
      type("one\r")
      repl.start
      await([:input, ''])
      turns = []
      @keys.close
      repl.run { |line| turns << line }
      repl.stop

      assert_equal ['one'], turns
    end
  end

  describe '#take' do
    it 'draws the count left behind the line it takes' do
      type("one\r")

      session do |line|
        next unless line == 'one'

        type("two\rthree\r")
        @keys.close
        await([:queued, 2])
      end

      assert_equal [1, 0, 0], @frame.counts.last(3)
    end

    it 'takes the lines queued behind a turn ahead of a job exit' do
      runtime = WatchedRuntime.new
      repl.watch(runtime)
      type("one\r")

      turns = session do |line|
        next @keys.close unless line == 'one'

        type("two\r")
        await([:queued, 1])
        runtime.exit_job
      end

      assert_equal ['one', 'two', :job_exit], turns
    end

    it 'ends once the keys have ended and nothing is queued' do
      @keys.close

      assert_empty session
    end

    it 'hints at the second Ctrl-C after the first while idle' do
      signalling
      press(:ctrl_c)
      begin_session
      await([:status, hint])
      @keys.close
      finish

      assert_equal [hint], @frame.statuses
    end

    it 'ends on a second Ctrl-C while idle' do
      signalling
      press(:ctrl_c)
      begin_session
      await([:status, hint])
      press(:ctrl_c)
      finish

      assert_equal :stop, logged.last
    end
  end

  describe '#job_exit' do
    before do
      @runtime = WatchedRuntime.new
    end

    it 'takes exits that landed together as one' do
      repl.watch(@runtime)
      2.times { @runtime.exit_job }

      assert_equal([:job_exit], session { @keys.close })
    end

    it 'drops an exit once the input has ended' do
      repl.watch(@runtime)
      type("one\r")

      turns = session do
        @runtime.exit_job
        press(:ctrl_d, :ctrl_c)
        @interrupts.pop(timeout: timeout_seconds)
      end

      assert_equal ['one'], turns
    end

    it 'disarms the exit for the turn it starts' do
      signalling.watch(@runtime)
      press(:ctrl_c)
      begin_session
      await([:status, hint])
      @runtime.exit_job
      await([:status, ''])
      press(:ctrl_c)
      await([:status, hint])
      @keys.close
      finish

      assert_equal 2, @frame.statuses.count(hint)
    end
  end

  describe '#read' do
    it 'shows the peek each key it hands on' do
      press(:ctrl_t)
      type('a')
      @keys.close

      session

      assert_equal %i[ctrl_t text], Array.new(@peek.pressed.size) { @peek.pressed.pop }
    end

    it 'ends an ask in flight when the keys end' do
      answer = :unanswered
      type("one\r")
      begin_session { answer = repl.ask('who?', options: nil, secret: false) }
      await([:asked, 'who?', nil, false])
      @keys.close
      finish

      assert_nil answer
    end
  end

  describe '#hand_on' do
    it 'hands Ctrl-C to an ask in flight' do
      type("one\r")
      begin_session { repl.ask('who?', options: nil, secret: false) }
      await([:asked, 'who?', nil, false])
      press(:ctrl_c)
      @keys.close
      finish

      assert_includes logged, [:interrupted, 'who?']
    end

    it 'sends Ctrl-C on as an interrupt' do
      press(:ctrl_c)
      @keys.close

      session

      assert_equal 1, @interrupts.size
    end

    it 'keeps Ctrl-C off the input line' do
      press(:ctrl_c)
      @keys.close

      session

      assert_empty @frame.lines
    end

    it 'draws the edited line in the footer' do
      type('hi')
      @keys.close

      session

      assert_equal %w[h hi], @frame.lines
    end
  end

  describe '#press' do
    it 'clears the hint on the next key' do
      signalling
      press(:ctrl_c)
      begin_session
      await([:status, hint])
      type('a')
      @keys.close
      finish

      assert_equal [hint, ''], @frame.statuses
    end

    it 'disarms the exit on a key between two Ctrl-Cs' do
      signalling
      press(:ctrl_c)
      begin_session
      await([:status, hint])
      type('a')
      await([:input, 'a'])
      press(:ctrl_c)
      await([:status, hint])
      @keys.close
      finish

      assert_equal 2, @frame.statuses.count(hint)
    end
  end

  describe '#edit' do
    it 'clears the footer line on Enter' do
      type("hi\r")
      @keys.close

      session

      assert_equal '', @frame.lines.last
    end

    it 'sends the selected command on Enter while the palette is open' do
      repl.watch(WatchedRuntime.new('model'))
      type("/mo\r")
      @keys.close

      assert_equal ['/model'], session
    end

    it 'sends a multi-line input on Enter' do
      type('a')
      press(:newline)
      type("b\r")
      @keys.close

      assert_equal ["a\nb"], session
    end

    it 'recalls a submitted line from the history' do
      type("hi\r")
      press(:up)
      @keys.close

      session

      assert_equal 'hi', @frame.lines.last
    end

    it 'ends on Ctrl-D on an empty line' do
      press(:ctrl_d)

      session

      assert_equal :stop, logged.last
    end

    it 'ignores Ctrl-D while the line has text' do
      type('one')
      press(:ctrl_d)
      type("\r")
      @keys.close

      assert_equal ['one'], session
    end

    it 'completes from the commands reloaded into the Runtime' do
      runtime = WatchedRuntime.new('auth')
      repl.watch(runtime)
      begin_session
      type('/')
      await([:input, '/'])
      runtime.reload('model')
      type('m')
      @keys.close
      finish

      assert_equal %w[model], @frame.palettes.last
    end
  end

  describe '#enqueue' do
    it 'counts a line submitted during a turn' do
      type("one\r")

      session do |line|
        next unless line == 'one'

        type("two\r")
        @keys.close
        await([:queued, 1])
      end

      assert_includes @frame.counts, 1
    end

    it 'draws no count for a line submitted while idle' do
      type("one\r")
      @keys.close

      session

      assert_equal [0, 0], @frame.counts
    end
  end

  describe '#close' do
    it 'runs what is already queued before the loop ends' do
      type("one\r")

      turns = session do |line|
        next unless line == 'one'

        type("two\r")
        press(:ctrl_d)
        await([:queued, 1])
      end

      assert_equal %w[one two], turns
    end

    it 'keeps reading the keys until the queue has drained' do
      seen = nil
      type("one\r")

      session do |_line|
        press(:ctrl_d, :ctrl_c)
        seen = @interrupts.pop(timeout: timeout_seconds)
      end

      assert_equal :interrupt, seen
    end
  end
end
