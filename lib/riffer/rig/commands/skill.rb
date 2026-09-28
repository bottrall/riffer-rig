# frozen_string_literal: true

module Riffer::Rig::Commands::Skill
  extend self

  # @rbs skill: Riffer::Skills::Frontmatter
  # @rbs return: Riffer::Rig::Command
  def command(skill)
    Riffer::Rig::Command.new("skill:#{skill.name}", description: skill.description, extension: 'core') do |ctx|
      run(ctx, skill)
    end
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs skill: Riffer::Skills::Frontmatter
  # @rbs return: void
  def run(ctx, skill)
    skills = ctx.runtime.agent.context.skills
    return ctx.host.notify("Skill #{skill.name} is no longer available", level: :error) unless skills

    # Context#read, not #activate: a skill the user runs stays in the model's
    # catalog, and only the model's own activations are recorded.
    content = skills.adapter.render_activation(skill, skills.read(skill.name))
    ctx.emit(Riffer::Rig::Events::SkillActivated.new(skill.name))
    ctx.prompt([content, ctx.args.strip].reject(&:empty?).join("\n\n"))
  end
end
