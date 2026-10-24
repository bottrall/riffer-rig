# frozen_string_literal: true

module Riffer::Rig::Commands::Switch
  extend self

  SAVE = '--save' #: String

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs label: String
  # @rbs shown: String
  # @rbs current: String?
  # @rbs unset: String
  # @rbs saved_to: String
  # @rbs store: ^(String) -> String?
  # @rbs &switch: (String) -> bool
  # @rbs return: void
  def run(ctx, label:, shown:, current:, unset:, saved_to:, store:, &switch)
    words = ctx.args.split
    save = words.delete(SAVE)
    value = words.join(' ')

    if value.empty?
      return ctx.say("#{label}: #{shown}") unless save
      return ctx.say(unset) unless current

      refusal = store.call(current)
      return ctx.host.notify(refusal, level: :error) if refusal

      return ctx.say("Saved #{current} to #{saved_to}")
    end

    return unless yield(value)

    refusal = store.call(value) if save
    ctx.host.notify(refusal, level: :error) if refusal
    saved = save && !refusal
    ctx.say(saved ? "#{label} switched to #{value} and saved to #{saved_to}" : "#{label} switched to #{value}")
  end
end
