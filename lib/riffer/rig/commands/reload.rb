# frozen_string_literal: true

module Riffer::Rig::Commands::Reload
  extend self

  # @rbs reloader: Riffer::Rig::Loader::Reloader
  # @rbs return: Riffer::Rig::Command
  def command(reloader)
    Riffer::Rig::Command.new(
      'reload',
      description: 'Reload the rig.rb files, settings, credentials and trust',
      extension: :core
    ) { |ctx| run(reloader, ctx) }
  end

  # @rbs reloader: Riffer::Rig::Loader::Reloader
  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs return: void
  def run(reloader, ctx)
    reloaded = reloader.reload(ctx.runtime, force: true)
    ctx.say('Reloaded') if reloaded.is_a?(Riffer::Rig::Runtime)
  end
end
