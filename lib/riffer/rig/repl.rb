# frozen_string_literal: true

class Riffer::Rig::REPL
  EXIT_COMMANDS = ['/exit', '/quit'].freeze
  SKILL_COMMAND = %r{\A/skill:([a-z0-9]+(?:-[a-z0-9]+)*)(?:\s+(.*))?\z}m

  def initialize(agent:, renderer:, input: $stdin, output: $stdout, theme: Riffer::Rig::UI::Theme.for(output), animator: Riffer::Rig::UI::Animator.new(io: output, theme:), smoother: Riffer::Rig::UI::Smoother.new(io: output, theme:, sink: Riffer::Rig::UI::MarkdownPainter.new(io: output, theme:)), cursor: Riffer::Rig::UI::Cursor.new(io: output, theme:))
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
  end

  private

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
      when Riffer::StreamEvents::ToolCallDone, Riffer::StreamEvents::SkillActivation, Riffer::StreamEvents::TokenUsageDone
        # The spinner shares its line with what's about to print, and tool
        # execution plus the next model invocation emit no events — stop it for
        # the render, then bring it straight back to cover the silent stretch.
        @animator.stop
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
    @output.puts
  rescue StandardError => e
    @output.puts("\nError: #{e.message}")
  ensure
    @smoother.finish
    @animator.stop
    @cursor.show
  end

  def run_skill_command(name, args)
    block = activate_skill(name)
    return if block.nil?

    run_turn([block, args].reject(&:empty?).join("\n\n"))
  end

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

  def skill_block(name, body)
    "<skill name=\"#{name}\">\n#{body}\n</skill>"
  end

  # Tool results can land mid-animation (tool execution emits no stream events,
  # so the indicator is up); stop it around the line so its next frame doesn't
  # erase what we printed.
  def render_tool_result(message)
    return unless message.is_a?(Riffer::Messages::Tool)

    @animator.stop
    @renderer.render_tool_result(message)
    @animator.start
  end
end
