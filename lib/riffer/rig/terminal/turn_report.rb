# frozen_string_literal: true

module Riffer::Rig::Terminal::TurnReport
  extend self

  INDENT = 2 #: Integer

  INTERRUPTED = 'interrupted'

  # @rbs turn: Riffer::Rig::Terminal::TurnBuffer
  # @rbs session: Riffer::Providers::TokenUsage?
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String
  def call(turn, session, theme:, width:)
    answer = turn.answer
    closing = turn.interrupted? ? INTERRUPTED : footer(turn.stats, session)
    blocks = [
      *(wrap(answer.gsub(Riffer::Rig::Terminal::Markdown::CONTROL, ''), width) if answer),
      theme.dim(wrap(closing, width))
    ]
    blocks.map { |block| "\n#{block}\n" }.join
  end

  private

  # @rbs stats: Riffer::Rig::Terminal::TurnBuffer::Stats
  # @rbs session: Riffer::Providers::TokenUsage?
  # @rbs return: String
  def footer(stats, session)
    usage = stats.usage
    minutes, seconds = stats.wall_time.to_i.divmod(60)
    [
      "#{stats.steps} #{stats.steps == 1 ? 'step' : 'steps'}",
      format('%<minutes>02d:%<seconds>02d', minutes: minutes, seconds: seconds),
      *([*Riffer::Rig::Terminal::Tally.tokens(usage), *Riffer::Rig::Terminal::Tally.cost(usage)] if usage),
      *("session #{Riffer::Rig::Terminal::Tally.call(session)}" if session)
    ].join(' · ')
  end

  # @rbs text: String
  # @rbs width: Integer?
  # @rbs return: String
  def wrap(text, width)
    wrapper = Riffer::Rig::Terminal::Wrapper.new(width: width, indent: INDENT)
    (wrapper << "#{text}\n").gsub(/\A\n+|\n+\z/, '')
  end
end
