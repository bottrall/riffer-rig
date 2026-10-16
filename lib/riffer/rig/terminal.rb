# frozen_string_literal: true

class Riffer::Rig::Terminal
  EXIT_COMMANDS = %w[/exit /quit].freeze #: Array[String]

  NEW_COMMAND = 'new' #: String

  RESUME_COMMAND = 'resume' #: String

  NEW_USAGE = 'Usage: /new' #: String

  RESUME_USAGE = 'Usage: /resume [--all]' #: String

  SLASH_COMMAND = %r{\A/(\S+)\s*(.*)\z}m #: Regexp

  EXIT_HINT = 'Press Ctrl-C again to exit.'

  FAREWELL = 'see you on the next riff.'

  # @rbs @input: IO
  # @rbs @host: Riffer::Rig::Hosts::_Host
  # @rbs @renderer: Riffer::Rig::Terminal::Renderer
  # @rbs @opening: Riffer::Rig::Terminal::Opening
  # @rbs @sessions: Riffer::Rig::Terminal::_Sessions
  # @rbs @picker: Riffer::Rig::Terminal::Picker
  # @rbs @turns: Riffer::Rig::Terminal::_TurnDisplay
  # @rbs @repl: Riffer::Rig::Terminal::Repl?

  # @rbs input: IO
  # @rbs output: IO
  # @rbs version: String
  # @rbs no_color: bool
  # @rbs sessions: Riffer::Rig::Terminal::_Sessions
  # @rbs return: Riffer::Rig::Terminal
  def self.for(input:, output:, version:, sessions:, no_color: false)
    theme = Theme.for(output, no_color: no_color)
    clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    frame = Frame.new(io: output, theme: theme) if input.tty?
    unless frame&.measure
      opening = Opening.new(io: output, theme:, version:, sessions:)
      turns = QuietDisplay.new(io: output, theme: theme, clock: clock)
      return assemble(input:, renderer: Renderer.new(io: output, theme: theme), sessions:, opening:, turns:)
    end

    pipeline = KeyPipeline.new(input: input, output: output)
    console = Console.new(frame: frame, pipeline: pipeline)
    asks = Queue.new #: Thread::Queue[Riffer::Rig::Terminal::Key]
    peek = Peek.new(frame: frame)
    repl = Repl.new(
      console: console,
      frame: frame,
      keys: pipeline.keys,
      asks: asks,
      prompter: FramePrompter.new(frame: frame, keys: asks, theme: theme),
      peek: peek,
      interrupt: -> { Process.kill('INT', Process.pid) }
    )
    opening = Opening.new(
      io: console,
      theme: theme,
      version: version,
      sessions: sessions,
      jobs: JobCounter.new(footer: frame),
      repl: repl
    )
    turns = TickerDisplay.new(
      frame: frame,
      theme: theme,
      peek: peek,
      pricing: Riffer.config.pricing,
      random: Random.new,
      clock: clock
    )
    assemble(input:, renderer: Renderer.new(io: console, theme: theme), sessions:, opening:, turns:, repl:)
  end

  # @rbs input: IO
  # @rbs renderer: Riffer::Rig::Terminal::Renderer
  # @rbs sessions: Riffer::Rig::Terminal::_Sessions
  # @rbs opening: Riffer::Rig::Terminal::Opening
  # @rbs turns: Riffer::Rig::Terminal::_TurnDisplay
  # @rbs repl: Riffer::Rig::Terminal::Repl?
  # @rbs return: Riffer::Rig::Terminal
  def self.assemble(input:, renderer:, sessions:, opening:, turns:, repl: nil)
    prompter = repl || BlockingPrompter.new(input: input, renderer: renderer)
    host = Riffer::Rig::Terminal::Host.new(prompter: prompter, renderer: renderer)
    picker = Picker.new(prompter: prompter, renderer: renderer, host: host, sessions: sessions)
    new(input:, host:, renderer:, opening:, sessions:, picker:, turns:, repl:)
  end
  private_class_method :assemble

  # @rbs input: IO
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs renderer: Riffer::Rig::Terminal::Renderer
  # @rbs opening: Riffer::Rig::Terminal::Opening
  # @rbs sessions: Riffer::Rig::Terminal::_Sessions
  # @rbs picker: Riffer::Rig::Terminal::Picker
  # @rbs turns: Riffer::Rig::Terminal::_TurnDisplay
  # @rbs repl: Riffer::Rig::Terminal::Repl?
  # @rbs return: void
  def initialize(input:, host:, renderer:, opening:, sessions:, picker:, turns:, repl: nil)
    @input = input
    @host = host
    @renderer = renderer
    @opening = opening
    @sessions = sessions
    @picker = picker
    @turns = turns
    @repl = repl
  end

  # @rbs open_picker: bool
  # @rbs return: Integer
  def run(open_picker: false)
    # Ruby keeps a SIGINT inherited as ignored, but the idle prompt and the
    # picker need the Interrupt its own handler raises.
    inherited = Signal.trap('INT', 'DEFAULT')
    begin
      run_session(open_picker)
    ensure
      Signal.trap('INT', inherited)
    end
  end

  private

  # @rbs open_picker: bool
  # @rbs return: Integer
  def run_session(open_picker)
    @repl&.start
    runtime = start(open_picker: open_picker)
    return 1 unless runtime

    begin
      @opening.call(runtime)
      queued = @repl
      queued ? drain(queued, runtime) : repl(runtime)
      @renderer.notice(FAREWELL)
      0
    ensure
      runtime.close
    end
  ensure
    @repl&.stop
  end

  # @rbs open_picker: bool
  # @rbs return: Riffer::Rig::Runtime?
  def start(open_picker:)
    session = @picker.open(all: false) if open_picker
    return build { @sessions.start(@host) } unless session

    resumed = build { @sessions.resume(@host, session.id) }
    return resumed if resumed

    @renderer.notify(@sessions.missing(session.id), :info)
    build { @sessions.start(@host) }
  end

  # @rbs &build: () -> Riffer::Rig::Runtime?
  # @rbs return: Riffer::Rig::Runtime?
  def build(&)
    yield
  rescue Riffer::Rig::Loader::ConfigurationError => e
    @renderer.error(e.message)
    nil
  rescue Interrupt
    @renderer.newline
    nil
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def repl(runtime)
    armed = false
    loop do
      case (line = read_line)
      when nil then break
      when :interrupt
        break if armed

        armed = true
        @renderer.notice(EXIT_HINT)
      else
        armed = false
        text = line.strip
        break if EXIT_COMMANDS.include?(text)

        runtime = dispatch(runtime, text) unless text.empty?
      end
    end
  end

  # @rbs return: String | :interrupt | nil
  def read_line
    @renderer.prompt
    @input.gets
  rescue Interrupt
    :interrupt
  end

  # @rbs queued: Riffer::Rig::Terminal::Repl
  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def drain(queued, runtime)
    queued.run do |entry|
      next deliver_job_exits(runtime) if entry == :job_exit

      # A pasted line can carry control characters the terminal would act on.
      @renderer.echo(LineEditor.new(before: entry).printable_before)
      break if EXIT_COMMANDS.include?(entry)

      runtime = dispatch(runtime, entry)
    end
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def deliver_job_exits(runtime)
    # An exit delivered inside a turn, or dropped with a swapped-out Runtime,
    # leaves nothing to start one for.
    exits = runtime.pending_job_exit_count
    return if exits.zero?

    @renderer.notice("#{exits} background #{exits == 1 ? 'job' : 'jobs'} exited")
    turn(runtime) { |emit| runtime.follow_up(&emit) }
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs text: String
  # @rbs return: Riffer::Rig::Runtime
  def dispatch(runtime, text)
    command = SLASH_COMMAND.match(text)
    if command
      case command[1].to_s
      when NEW_COMMAND then return command_new(runtime, command[2].to_s)
      when RESUME_COMMAND then return command_resume(runtime, command[2].to_s)
      end

      turn(runtime) { |emit| runtime.run_command(command[1].to_s, command[2].to_s, &emit) }
    else
      turn(runtime) { |emit| runtime.prompt(text, &emit) }
    end
    runtime
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs args: String
  # @rbs return: Riffer::Rig::Runtime
  def command_new(runtime, args)
    return usage(runtime, NEW_USAGE) unless args.strip.empty?

    fresh = build { @sessions.fresh(@host) }
    return runtime unless fresh

    swap(runtime, fresh)
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs args: String
  # @rbs return: Riffer::Rig::Runtime
  def command_resume(runtime, args)
    stripped = args.strip
    return usage(runtime, RESUME_USAGE) unless stripped.empty? || stripped == '--all'

    session = @picker.open(all: stripped == '--all')
    return runtime unless session

    resumed = build { @sessions.resume(@host, session.id) }
    return missing(runtime, session) unless resumed

    swap(runtime, resumed)
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs usage: String
  # @rbs return: Riffer::Rig::Runtime
  def usage(runtime, usage)
    @renderer.notice(usage)
    runtime
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs session: Riffer::Rig::Terminal::Session
  # @rbs return: Riffer::Rig::Runtime
  def missing(runtime, session)
    @renderer.notify(@sessions.missing(session.id), :info)
    runtime
  end

  # @rbs previous: Riffer::Rig::Runtime
  # @rbs next_runtime: Riffer::Rig::Runtime
  # @rbs return: Riffer::Rig::Runtime
  def swap(previous, next_runtime)
    previous.close
    @opening.call(next_runtime)
    next_runtime
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs &block: (^(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void) -> void
  # @rbs return: void
  def turn(runtime, &)
    # Runtime#cancel takes a Mutex, which Ruby refuses inside a trap handler,
    # so the handler hands the cancel to a thread.
    previous = Signal.trap('INT') { Thread.new { @turns.cancel(runtime) } }
    begin
      @turns.start(runtime)
      yield(->(event) { render(runtime, event) })
    rescue StandardError => e
      @renderer.error("Error: #{e.message}")
    ensure
      Signal.trap('INT', previous)
      @turns.finish(runtime)
    end
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: void
  def render(runtime, event)
    case event
    when Riffer::Rig::Events::CommandOutput
      @renderer.notice(event.text)
    when Riffer::Rig::Events::TurnEnd
      @turns.absorb(event)
      @turns.finish(runtime)
      # A command can prompt more than once, and each turn is shown as its own.
      @turns.start(runtime)
    else
      @turns.absorb(event)
    end
  end
end
