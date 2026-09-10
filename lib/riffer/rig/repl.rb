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
  # @rbs @input: untyped
  # @rbs @output: untyped
  # @rbs @pending_tool_calls: Array[Riffer::StreamEvents::ToolCallDone]

  # @rbs ?agent: Riffer::Agent
  # @rbs ?renderer: Riffer::Rig::UI::Renderer
  # @rbs input: untyped
  # @rbs output: untyped
  # @rbs ?theme: Riffer::Rig::UI::Theme
  # @rbs ?animator: Riffer::Rig::UI::Animator
  # @rbs ?smoother: Riffer::Rig::UI::Smoother
  # @rbs ?cursor: Riffer::Rig::UI::Cursor
  # @rbs return: void
  def initialize(agent:, renderer:, input: $stdin, output: $stdout, theme: Riffer::Rig::UI::Theme.for(output), animator: Riffer::Rig::UI::Animator.new(io: output, theme:), smoother: Riffer::Rig::UI::Smoother.new(io: output, theme:), cursor: Riffer::Rig::UI::Cursor.new(io: output, theme:))
    @agent = agent
    @renderer = renderer
    @animator = animator
    @smoother = smoother
    @cursor = cursor
    @theme = theme
    @input = input
    @output = output
    @pending_tool_calls = []
    @agent.session.on_message { |message| render_tool_result(message) }
  end

  # @rbs return: Symbol
  def run
    loop do
      @output.print("\n#{@theme.pink('›')} ")
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

    @output.puts("\n#{@theme.grey('see you on the next riff.')}")
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
        # Round bookkeeping: nothing renders, so the indicator just carries on
        # (or stays parked while the smoother finishes typing earlier text).
        next
      when Riffer::StreamEvents::ToolCallDone
        # Tool call lines are held back so the round's stats line can print
        # above them (see flush_pending_tool_calls).
        @pending_tool_calls << event
        next
      when Riffer::StreamEvents::SkillActivation, Riffer::StreamEvents::TokenUsageDone
        # The spinner shares its line with what's about to print, and tool
        # execution plus the next model invocation emit no events — stop it for
        # the render, then bring it straight back to cover the silent stretch.
        # Stats print before any pending tool call lines (see below).
        @animator.stop
        @renderer.render(event)
        flush_pending_tool_calls
        @animator.start
        next
      else
        @animator.stop
      end
      flush_pending_tool_calls
      @renderer.render(event)
    end
    @animator.stop
    flush_pending_tool_calls
    @smoother.finish
    @output.puts
  rescue StandardError => e
    @animator.stop
    flush_pending_tool_calls
    @output.puts("\nError: #{e.message}")
  ensure
    @smoother.finish
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
      @output.puts(@theme.grey('No skills configured.'))
      return
    end

    # TODO: read the body without mutating activation state once riffer exposes
    # a non-mutating Context#read. `activate` marks the skill model-activated as
    # a side effect, which drops it from the model's catalog after manual use.
    body = skills.activate(name)
    @output.puts(@theme.magenta("✦ skill: #{name}"))
    skill_block(name, body)
  rescue Riffer::ArgumentError
    @output.puts(@theme.red("Unknown skill: #{name}"))
    nil
  rescue StandardError => e
    @output.puts(@theme.red("Error activating skill: #{e.message}"))
    nil
  end

  # @rbs name: String
  # @rbs body: String
  # @rbs return: String
  def skill_block(name, body)
    "<skill name=\"#{name}\">\n#{body}\n</skill>"
  end

  # Tool call lines print below their round's stats line to reflect the actual
  # timeline (usage is reported when the model stream closes, after the calls
  # were decided). ToolCallDone events are therefore held until the stats line
  # or the next event forces them out. Callers must have the spinner stopped —
  # the flush renders between their existing stop/start pair.
  #
  # @rbs return: void
  def flush_pending_tool_calls
    return if @pending_tool_calls.empty?

    @pending_tool_calls.each { |event| @renderer.render(event) }
    @pending_tool_calls = []
  end

  # Tool results can land mid-animation (tool execution emits no stream events,
  # so the indicator is up); stop it around the line so its next frame doesn't
  # erase what we printed.
  #
  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def render_tool_result(message)
    return unless message.is_a?(Riffer::Messages::Tool)

    @animator.stop
    @renderer.render_tool_result(message)
    @animator.start
  end
end
