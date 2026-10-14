# frozen_string_literal: true

module Riffer::Rig::Commands::Cost
  extend self

  NO_USAGE = 'No usage recorded yet'
  NO_TURN_USAGE = 'no usage'
  LABEL_WIDTH = 8

  # @rbs return: Riffer::Rig::Command
  def command
    Riffer::Rig::Command.new(
      'cost',
      description: "Show the session's token usage and cost, turn by turn",
      extension: :core
    ) { |ctx| run(ctx) }
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs return: void
  def run(ctx)
    session = ctx.runtime.tally
    return ctx.say(NO_USAGE) unless session

    breakdown = turns(ctx.runtime.agent.session.messages).each_with_index.map do |turn, index|
      line("turn #{index + 1}", Riffer::Rig::Runtime::Usage.sum(turn))
    end
    ctx.say([line('session', session), *breakdown].join("\n"))
  end

  private

  # @rbs messages: Array[Riffer::Messages::Base]
  # @rbs return: Array[Array[Riffer::Messages::Base]]
  def turns(messages)
    messages.drop_while { |message| !message.is_a?(Riffer::Messages::User) }.slice_before(Riffer::Messages::User).to_a
  end

  # @rbs label: String
  # @rbs usage: Riffer::Providers::TokenUsage?
  # @rbs return: String
  def line(label, usage)
    "#{label.ljust(LABEL_WIDTH)}  #{usage ? figures(usage) : NO_TURN_USAGE}"
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: String
  def figures(usage)
    cache = { cache_write: usage.cache_write_tokens, cache_read: usage.cache_read_tokens }
    cost = usage.cost
    [
      "↑#{usage.input_tokens}",
      "↓#{usage.output_tokens}",
      *cache.filter_map { |name, count| "#{name}:#{count}" if count&.positive? },
      *(format('~$%.4f', cost) if cost)
    ].join(' · ')
  end
end
