# frozen_string_literal: true

module Riffer::Rig::Commands::Reasoning
  extend self

  SAVE = '--save' #: String
  SAVED_TO = '~/.riffer/settings.json' #: String
  DEFAULT = 'default' #: String

  # @rbs return: Riffer::Rig::Command
  def command
    Riffer::Rig::Command.new(
      'reasoning',
      description: 'Switch the reasoning level for this session: /reasoning high, /reasoning --save',
      extension: :core
    ) { |ctx| run(ctx) }
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs return: void
  def run(ctx)
    words = ctx.args.split
    save = words.delete(SAVE)
    level = words.join(' ')

    if level.empty?
      current = ctx.runtime.reasoning
      return ctx.say("Reasoning: #{current || DEFAULT}") unless save
      return ctx.say('No reasoning level is in effect to save') unless current

      refusal = Riffer::Rig::Settings::File.store_reasoning(current)
      return ctx.host.notify(refusal, level: :error) if refusal

      return ctx.say("Saved #{current} to #{SAVED_TO}")
    end

    levels = Riffer::Rig::Settings::ModelOptions.levels_for(ctx.runtime.model)
    return ctx.say(hint(ctx.runtime.model, levels)) unless levels.include?(level)

    ctx.runtime.reasoning = level
    refusal = Riffer::Rig::Settings::File.store_reasoning(level) if save
    ctx.host.notify(refusal, level: :error) if refusal
    saved = save && !refusal
    ctx.say(saved ? "Reasoning switched to #{level} and saved to #{SAVED_TO}" : "Reasoning switched to #{level}")
  end

  private

  # @rbs model: String
  # @rbs levels: Array[String]
  # @rbs return: String
  def hint(model, levels)
    return "#{Riffer::Rig::Settings::ModelOptions.provider_for(model)} accepts no reasoning level" if levels.empty?

    "Use /reasoning level, with a level from: #{levels.join(', ')}"
  end
end
