# frozen_string_literal: true

class Riffer::Rig::REPL
  EXIT_COMMANDS = ['/exit', '/quit'].freeze
  SKILL_COMMAND = %r{\A/skill:([a-z0-9]+(?:-[a-z0-9]+)*)(?:\s+(.*))?\z}m

  def initialize(agent:, renderer:, input: $stdin, output: $stdout, theme: Riffer::Rig::UI::Theme.for(output), animator: Riffer::Rig::UI::Animator.new(io: output, theme:), smoother: Riffer::Rig::UI::Smoother.new(io: output, theme:))
    @agent = agent
    @renderer = renderer
    @animator = animator
    @smoother = smoother
    @theme = theme
    @input = input
    @output = output
    @agent.session.on_message { |message| @renderer.render_tool_result(message) }
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
    @animator.start_thinking
    @smoother.start
    @agent.stream(prompt).each do |event|
      @animator.stop_thinking
      @renderer.render(event)
    end
    @smoother.finish
    @output.puts
  rescue StandardError => e
    @output.puts("\nError: #{e.message}")
  ensure
    @smoother.finish
    @animator.stop_thinking
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
end
