# frozen_string_literal: true

module Riffer::Rig::Commands::Reasoning
  extend self

  SAVE = '--save' #: String
  DEFAULT = 'default' #: String

  # @rbs settings_path: String
  # @rbs return: Riffer::Rig::Command
  def command(settings_path:)
    Riffer::Rig::Command.new(
      'reasoning',
      description: 'Switch the reasoning level for this session: /reasoning high, /reasoning --save',
      extension: :core
    ) { |ctx| run(ctx, settings_path:) }
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs settings_path: String
  # @rbs return: void
  def run(ctx, settings_path:)
    words = ctx.args.split
    save = words.delete(SAVE)
    level = words.join(' ')

    if level.empty?
      current = ctx.runtime.reasoning
      return ctx.say("Reasoning: #{current || DEFAULT}") unless save
      return ctx.say('No reasoning level is in effect to save') unless current

      refusal = Riffer::Rig::Settings::File.store_reasoning(current, path: settings_path)
      return ctx.host.notify(refusal, level: :error) if refusal

      return ctx.say("Saved #{current} to #{settings_path}")
    end

    rejection = Riffer::Rig::Settings::ModelOptions.reasoning_rejection(level)
    return ctx.say(rejection) if rejection

    ctx.runtime.reasoning = level
    refusal = Riffer::Rig::Settings::File.store_reasoning(level, path: settings_path) if save
    ctx.host.notify(refusal, level: :error) if refusal
    saved = save && !refusal
    ctx.say(saved ? "Reasoning switched to #{level} and saved to #{settings_path}" : "Reasoning switched to #{level}")
  end
end
