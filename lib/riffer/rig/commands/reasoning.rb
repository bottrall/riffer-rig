# frozen_string_literal: true

module Riffer::Rig::Commands::Reasoning
  extend self

  SAVE = '--save' #: String
  SAVED_TO = '~/.riffer/settings.json' #: String

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
      return ctx.say("Reasoning: #{current || Riffer::Rig::Runtime::DEFAULT_REASONING_LABEL}") unless save
      return ctx.say('No reasoning level is in effect to save') unless current

      refusal = Riffer::Rig::Settings::File.store_reasoning(current)
      return ctx.host.notify(refusal, level: :error) if refusal

      return ctx.say("Saved #{current} to #{SAVED_TO}")
    end

    rejection = Riffer::Rig::Settings::ModelOptions.reasoning_rejection(level)
    return ctx.say(rejection) if rejection

    ctx.runtime.reasoning = level
    refusal = Riffer::Rig::Settings::File.store_reasoning(level) if save
    ctx.host.notify(refusal, level: :error) if refusal
    saved = save && !refusal
    ctx.say(saved ? "Reasoning switched to #{level} and saved to #{SAVED_TO}" : "Reasoning switched to #{level}")
  end
end
