# frozen_string_literal: true

module Riffer::Rig::Commands::Reasoning
  extend self

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
    current = ctx.runtime.reasoning
    Riffer::Rig::Commands::Switch.run(
      ctx,
      label: 'Reasoning',
      shown: current || DEFAULT,
      current: current,
      unset: 'No reasoning level is in effect to save',
      saved_to: settings_path,
      store: ->(level) { Riffer::Rig::Settings::File.store_reasoning(level, path: settings_path) }
    ) { |level| switched?(ctx, level) }
  end

  private

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs level: String
  # @rbs return: bool
  def switched?(ctx, level)
    rejection = Riffer::Rig::Settings::ModelOptions.reasoning_rejection(level)
    if rejection
      ctx.say(rejection)
      return false
    end

    ctx.runtime.reasoning = level
    true
  end
end
