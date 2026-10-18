# frozen_string_literal: true

class Riffer::Rig::Terminal
  EXIT_COMMANDS = %w[/exit /quit].freeze #: Array[String]

  NEW_COMMAND = 'new' #: String

  RESUME_COMMAND = 'resume' #: String

  HELP_COMMAND = 'help' #: String

  BUILTINS = [
    Builtin.new(NEW_COMMAND, description: 'Start a fresh session in place'),
    Builtin.new(RESUME_COMMAND, description: "Pick a session to resume: /resume --all for every directory's"),
    Builtin.new(HELP_COMMAND, description: "List this session's commands"),
    *EXIT_COMMANDS.map { |line| Builtin.new(line.delete_prefix('/'), description: 'End the session') }
  ].freeze #: Array[Riffer::Rig::Terminal::Builtin]

  NEW_USAGE = 'Usage: /new' #: String

  RESUME_USAGE = 'Usage: /resume [--all]' #: String

  HELP_USAGE = 'Usage: /help' #: String

  COMMAND_HINT = 'Type a command name after /'

  BARE_SLASH = %r{\A/(?:\s|\z)} #: Regexp

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
    width = -> { Frame.measure(output)&.last }
    frame = Frame.new(io: output, theme: theme, loading: true) if input.tty?
    unless frame&.measure
      opening = Opening.new(io: output, theme:, version:, sessions:, width:)
      turns = QuietDisplay.new(io: output, theme: theme, clock: clock)
      return assemble(input:, renderer: Renderer.new(io: output, theme:, width:), sessions:, opening:, turns:)
    end

    pipeline = KeyPipeline.new(input: input, output: output)
    console = Console.new(frame: frame, pipeline: pipeline, loading: Loading.new(frame: frame, random: Random.new))
    asks = Queue.new #: Thread::Queue[Riffer::Rig::Terminal::Key]
    peek = Peek.new(frame: frame)
    repl = Repl.new(
      console: console,
      frame: frame,
      keys: pipeline.keys,
      asks: asks,
      prompter: FramePrompter.new(frame: frame, keys: asks, theme: theme),
      peek: peek,
      interrupt: -> { Process.kill('INT', Process.pid) },
      builtins: BUILTINS
    )
    opening = Opening.new(
      io: console,
      theme: theme,
      version: version,
      sessions: sessions,
      width: width,
      jobs: JobCounter.new(footer: frame),
      repl: repl
    )
    turns = TickerDisplay.new(
      frame: frame,
      theme: theme,
      peek: peek,
      catalog: Riffer.config.catalog,
      random: Random.new,
      clock: clock
    )
    renderer = Renderer.new(io: console, theme: theme, width: -> { frame.measure&.last })
    assemble(input:, renderer:, sessions:, opening:, turns:, repl:)
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
    session = @picker.open(all: false) if open_picker
    found = nil #: Riffer::Rig::Runtime?
    runtime = build { (found = find(session)) || @sessions.fresh(@host) }
    return 1 unless runtime

    begin
      @opening.call(runtime)
      notify_missing(session) unless found
      each_entry do |entry|
        next deliver_job_exits(runtime) if entry == :job_exit

        runtime = dispatch(runtime, entry)
      end
      @renderer.notice(FAREWELL)
      0
    ensure
      runtime.close
    end
  ensure
    @repl&.stop
  end

  # @rbs session: Riffer::Rig::Terminal::Session?
  # @rbs return: Riffer::Rig::Runtime?
  def find(session)
    session ? @sessions.resume(@host, session.id) : @sessions.find(@host)
  end

  # @rbs session: Riffer::Rig::Terminal::Session?
  # @rbs return: void
  def notify_missing(session)
    @renderer.notify(@sessions.missing(session&.id), :info) if session || @sessions.asked?
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

  # @rbs &block: (String | :job_exit) -> void
  # @rbs return: void
  def each_entry(&)
    queued = @repl
    queued ? drain(queued, &) : repl(&)
  end

  # @rbs &block: (String) -> void
  # @rbs return: void
  def repl
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

        yield text unless text.empty?
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
  # @rbs &block: (String | :job_exit) -> void
  # @rbs return: void
  def drain(queued)
    queued.run do |entry|
      next yield(entry) if entry == :job_exit

      @renderer.echo(entry)
      break if EXIT_COMMANDS.include?(entry)

      yield entry
    end
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def deliver_job_exits(runtime)
    # An exit delivered inside a turn, or dropped with a swapped-out Runtime,
    # leaves nothing to start one for.
    return if runtime.pending_job_exit_count.zero?

    # Exits that land after the wake are taken along with the first, and those
    # that land once the reply starts are told later in the turn, so the notice
    # waits for the reply and counts what was taken before it.
    taken = 0 #: Integer?
    announce = lambda do
      exits = taken
      taken = nil
      @renderer.notice(JobExitNotice.call(exits)) if exits&.positive?
    end
    turn(runtime) do |emit|
      runtime.follow_up do |event|
        case event
        when Riffer::Rig::Events::JobExit then taken += 1 if taken
        when Riffer::StreamEvents::Base, Riffer::Rig::Events::TurnEnd then announce.call
        end
        emit.call(event)
      end
    ensure
      announce.call
    end
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs text: String
  # @rbs return: Riffer::Rig::Runtime
  def dispatch(runtime, text)
    return notice(runtime, COMMAND_HINT) if BARE_SLASH.match?(text)

    command = Riffer::Rig::Command::INVOCATION.match(text)
    if command
      case command[1].to_s
      when NEW_COMMAND then return command_new(runtime, command[2].to_s)
      when RESUME_COMMAND then return command_resume(runtime, command[2].to_s)
      when HELP_COMMAND then return command_help(runtime, command[2].to_s)
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
    return notice(runtime, NEW_USAGE) unless args.strip.empty?

    fresh = build { @sessions.fresh(@host) }
    return runtime unless fresh

    swap(runtime, fresh)
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs args: String
  # @rbs return: Riffer::Rig::Runtime
  def command_resume(runtime, args)
    stripped = args.strip
    return notice(runtime, RESUME_USAGE) unless stripped.empty? || stripped == '--all'

    session = @picker.open(all: stripped == '--all')
    return runtime unless session

    resumed = build { @sessions.resume(@host, session.id) }
    return missing(runtime, session) unless resumed

    swap(runtime, resumed)
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs args: String
  # @rbs return: Riffer::Rig::Runtime
  def command_help(runtime, args)
    return notice(runtime, HELP_USAGE) unless args.strip.empty?

    notice(runtime, Help.call([*BUILTINS, *runtime.commands]))
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs message: String
  # @rbs return: Riffer::Rig::Runtime
  def notice(runtime, message)
    @renderer.notice(message)
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
      @renderer.error("Error: #{Riffer::Rig::Runtime::ErrorMessage.of(e)}")
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
