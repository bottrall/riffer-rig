# frozen_string_literal: true

class Riffer::Rig::Terminal
  EXIT_COMMANDS = %w[/exit /quit].freeze #: Array[String]

  SLASH_COMMAND = %r{\A/(\S+)\s*(.*)\z}m #: Regexp

  SKILL_COMMAND_PREFIX = 'skill:'

  EXIT_HINT = 'Press Ctrl-C again to exit.'

  FAREWELL = 'see you on the next riff.'

  # @rbs @input: IO
  # @rbs @host: Riffer::Rig::Hosts::_Host
  # @rbs @renderer: Riffer::Rig::Terminal::Renderer
  # @rbs @animator: Riffer::Rig::Terminal::Animator
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @version: String

  # @rbs input: IO
  # @rbs output: IO
  # @rbs version: String
  # @rbs no_color: bool
  # @rbs return: Riffer::Rig::Terminal
  def self.for(input:, output:, version:, no_color: false)
    theme = Theme.for(output, no_color: no_color)
    smoother = Smoother.new(io: output, theme: theme)
    renderer = Renderer.new(io: output, theme: theme, smoother: smoother, cursor: Cursor.new(io: output, theme: theme))
    animator = Animator.new(io: output, theme: theme)
    host = Riffer::Rig::Terminal::Host.new(input: input, renderer: renderer, animator: animator)
    new(input: input, host: host, renderer: renderer, animator: animator, theme: theme, version: version)
  end

  # @rbs input: IO
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs renderer: Riffer::Rig::Terminal::Renderer
  # @rbs animator: Riffer::Rig::Terminal::Animator
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs version: String
  # @rbs return: void
  def initialize(input:, host:, renderer:, animator:, theme:, version:)
    @input = input
    @host = host
    @renderer = renderer
    @animator = animator
    @theme = theme
    @version = version
  end

  # @rbs &build: (Riffer::Rig::Hosts::_Host) -> Riffer::Rig::Runtime
  # @rbs return: Integer
  def run(&build)
    runtime = load(build)
    return 1 unless runtime

    begin
      runtime.on_message { |message| render_tool_result(message) }
      reveal_banner(runtime)
      repl(runtime)
      @renderer.notice(FAREWELL)
      0
    ensure
      runtime.close
    end
  end

  private

  # @rbs build: ^(Riffer::Rig::Hosts::_Host) -> Riffer::Rig::Runtime
  # @rbs return: Riffer::Rig::Runtime?
  def load(build)
    build.call(@host)
  rescue Riffer::Rig::Loader::ConfigurationError => e
    @renderer.error(e.message)
    nil
  rescue Interrupt
    @renderer.newline
    nil
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: void
  def reveal_banner(runtime)
    skills = runtime.commands.count { |command| command.name.start_with?(SKILL_COMMAND_PREFIX) }
    lines = Banner.lines(
      @theme,
      model: runtime.model,
      cwd: runtime.cwd,
      skills: skills.zero? ? 'none' : skills.to_s,
      version: @version
    )
    @animator.reveal([lines])
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

        dispatch(runtime, text) unless text.empty?
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

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs text: String
  # @rbs return: void
  def dispatch(runtime, text)
    command = SLASH_COMMAND.match(text)
    turn(runtime) do |emit|
      if command
        runtime.run_command(command[1].to_s, command[2].to_s, &emit)
      else
        runtime.prompt(text, &emit)
      end
    end
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs &block: (^(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void) -> void
  # @rbs return: void
  def turn(runtime)
    # Runtime#cancel takes a Mutex, which Ruby refuses inside a trap handler,
    # so the handler hands the cancel to a thread.
    previous = Signal.trap('INT') { Thread.new { runtime.cancel } }
    begin
      @renderer.begin_turn
      start_animator
      yield(->(event) { render(runtime, event) })
    rescue StandardError => e
      @animator.stop
      @renderer.error("Error: #{e.message}")
    ensure
      Signal.trap('INT', previous)
      @animator.stop
      @renderer.end_turn
    end
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: void
  def render(runtime, event)
    case event
    when Riffer::StreamEvents::ReasoningDelta
      start_animator(:reasoning)
    when Riffer::StreamEvents::ReasoningDone, Riffer::StreamEvents::TokenUsageDone
      # Tool execution and the next model call emit no events, so the spinner
      # comes straight back on to cover the silent stretch.
      start_animator
    when Riffer::StreamEvents::TextDelta, Riffer::StreamEvents::ToolCallDone, Riffer::StreamEvents::Interrupt
      @animator.stop
      @renderer.render(event)
    when Riffer::StreamEvents::SkillActivation, Riffer::Rig::Events::SkillActivated
      @animator.stop
      @renderer.skill(event.name)
      start_animator
    when Riffer::Rig::Events::CommandOutput
      @animator.stop
      @renderer.notice(event.text)
    when Riffer::Rig::Events::TurnEnd
      @animator.stop
      @renderer.usage(event.usage, runtime.tally)
    end
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def render_tool_result(message)
    return unless message.is_a?(Riffer::Messages::Tool)

    @animator.stop
    @renderer.render_tool_result(message)
    start_animator
  end

  # @rbs mode: Symbol
  # @rbs return: void
  def start_animator(mode = :neutral)
    # The smoother's backlog may still be trickling out from streamed prose,
    # and spinner frames drawn mid-drain would carve `\r…\e[K` through a
    # half-printed sentence.
    @renderer.drain
    @animator.start(mode)
  end
end
