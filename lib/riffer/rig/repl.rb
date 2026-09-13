# frozen_string_literal: true

class Riffer::Rig::REPL
  EXIT_COMMANDS = ['/exit', '/quit'].freeze #: Array[String]

  SKILL_COMMAND = %r{\A/skill:([a-z0-9]+(?:-[a-z0-9]+)*)(?:\s+(.*))?\z}m #: Regexp

  # @rbs @agent: Riffer::Agent
  # @rbs @renderer: Riffer::Rig::UI::Renderer
  # @rbs @animator: Riffer::Rig::UI::Animator
  # @rbs @smoother: Riffer::Rig::UI::Smoother
  # @rbs @cursor: Riffer::Rig::UI::Cursor
  # @rbs @theme: Riffer::Rig::UI::Theme
  # @rbs @input: IO
  # @rbs @output: IO

  # @rbs agent: Riffer::Agent
  # @rbs renderer: Riffer::Rig::UI::Renderer
  # @rbs input: IO
  # @rbs output: IO
  # @rbs theme: Riffer::Rig::UI::Theme
  # @rbs animator: Riffer::Rig::UI::Animator
  # @rbs smoother: Riffer::Rig::UI::Smoother
  # @rbs cursor: Riffer::Rig::UI::Cursor
  # @rbs return: void
  def initialize(
    agent:,
    renderer:,
    input: $stdin,
    output: $stdout,
    theme: Riffer::Rig::UI::Theme.for(output),
    animator: Riffer::Rig::UI::Animator.new(io: output, theme:),
    smoother: Riffer::Rig::UI::Smoother.new(io: output, theme:),
    cursor: Riffer::Rig::UI::Cursor.new(io: output, theme:)
  )
    @agent = agent
    @renderer = renderer
    @animator = animator
    @smoother = smoother
    @cursor = cursor
    @theme = theme
    @input = input
    @output = output
    @agent.session.on_message { |message| render_tool_result(message) }
  end

  # @rbs return: Symbol
  def run
    loop do
      @renderer.prompt
      line = @input.gets
      break if line.nil?

      prompt = line.strip
      next if prompt.empty?
      break if EXIT_COMMANDS.include?(prompt)

      match = SKILL_COMMAND.match(prompt)

      if match
        run_skill_command(match[1], match[2].to_s.strip)
      else
        run_turn(prompt)
      end
    end

    print_block { @theme.grey('see you on the next riff.') }
    :done
  end

  private

  # @rbs prompt: String
  # @rbs return: void
  def run_turn(prompt)
    @cursor.hide
    @animator.start
    @smoother.start
    @agent.stream(prompt).each do |event|
      case event
      when Riffer::StreamEvents::ReasoningDelta
        @animator.start(:reasoning)
      when Riffer::StreamEvents::ReasoningDone
        @animator.start
      when Riffer::StreamEvents::ToolCallDelta, Riffer::StreamEvents::FinishReasonDone
        next
      when Riffer::StreamEvents::SkillActivation
        # Tool execution and the next model invocation emit no events, so the
        # spinner comes straight back on to cover the silent stretch.
        @animator.stop
        @renderer.render(event)
        @animator.start
        next
      when Riffer::StreamEvents::TokenUsageDone
        # Usage renders nothing inline — it flushes below the turn's output.
        # Restarting here covers the silent tool-execution stretch that follows.
        @renderer.render(event)
        @animator.start
        next
      else
        @animator.stop
      end
      @renderer.render(event)
    end
    @animator.stop
    @smoother.finish
    @renderer.flush_usage
  rescue StandardError => e
    @smoother.finish
    print_block { @theme.red("Error: #{e.message}") }
  ensure
    @animator.stop
    @cursor.show
  end

  # @rbs name: String
  # @rbs args: String
  # @rbs return: void
  def run_skill_command(name, args)
    block = activate_skill(name)
    return if block.nil?

    run_turn([block, args].reject(&:empty?).join("\n\n"))
  end

  # @rbs name: String
  # @rbs return: String?
  def activate_skill(name)
    skills = @agent.context.skills

    unless skills
      print_block { @theme.grey('No skills configured.') }
      return
    end

    # TODO: read the body without mutating activation state once riffer exposes
    # a non-mutating Context#read. `activate` marks the skill model-activated as
    # a side effect, which drops it from the model's catalog after manual use.
    body = skills.activate(name)
    print_block { @theme.magenta("✦ skill: #{name}") }
    skill_block(name, body)
  rescue Riffer::ArgumentError
    print_block { @theme.red("Unknown skill: #{name}") }
    nil
  rescue StandardError => e
    print_block { @theme.red("Error activating skill: #{e.message}") }
    nil
  end

  # @rbs name: String
  # @rbs body: String
  # @rbs return: String
  def skill_block(name, body)
    "<skill name=\"#{name}\">\n#{body}\n</skill>"
  end

  # Chrome lines that never pass through the renderer (errors, exit line) end
  # their line with a newline but leave the renderer's tool-group state alone —
  # they can only follow prose, never mid-group.
  #
  # @rbs &block: ^() -> String
  # @rbs return: void
  def print_block(&)
    @output.puts
    @output.puts(yield)
    @output.flush
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def render_tool_result(message)
    return unless message.is_a?(Riffer::Messages::Tool)

    @animator.stop
    @renderer.render_tool_result(message)
    @animator.start
  end
end
