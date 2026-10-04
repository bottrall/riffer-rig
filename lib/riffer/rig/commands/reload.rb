# frozen_string_literal: true

module Riffer::Rig::Commands::Reload
  extend self

  # @rbs loader: Riffer::Rig::Loader
  # @rbs return: Riffer::Rig::Command
  def command(loader)
    Riffer::Rig::Command.new(
      'reload',
      description: 'Reload the rig.rb files, settings, credentials and trust',
      extension: 'core'
    ) { |ctx| run(loader, ctx) }
  end

  # @rbs loader: Riffer::Rig::Loader
  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs return: void
  def run(loader, ctx)
    reloaded = loader.reload(ctx.runtime, force: true)
    ctx.say('Reloaded') if reloaded.is_a?(Riffer::Rig::Runtime)
  end
end
