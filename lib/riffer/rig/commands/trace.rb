# frozen_string_literal: true

module Riffer::Rig::Commands::Trace
  extend self

  NO_TURN = 'No turn recorded yet'

  # @rbs store: Riffer::Rig::Stores::_Reader
  # @rbs return: Riffer::Rig::Command
  def command(store)
    Riffer::Rig::Command.new(
      'trace',
      description: "Replay the last turn's activity from the session store",
      extension: :core
    ) { |ctx| run(store, ctx) }
  end

  # @rbs store: Riffer::Rig::Stores::_Reader
  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs return: void
  def run(store, ctx)
    lines = Riffer::Rig::Commands::Trace::Replay.lines(store.read(ctx.runtime.id))
    ctx.say(lines.empty? ? NO_TURN : lines.join("\n"))
  end
end
