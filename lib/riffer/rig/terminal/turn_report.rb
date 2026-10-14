# frozen_string_literal: true

module Riffer::Rig::Terminal::TurnReport
  extend self

  INDENT = 2 #: Integer

  INTERRUPTED = 'interrupted'

  # @rbs turn: Riffer::Rig::Terminal::TurnReport::_Turn
  # @rbs session: Riffer::Providers::TokenUsage?
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String
  def call(turn, session, theme:, width:)
    closing = turn.interrupted? ? INTERRUPTED : footer(turn.stats, session)
    blocks = [*answer(turn.answer.to_s, theme: theme, width: width), theme.dim(wrap(closing, width))]
    blocks.map { |block| "\n#{block}\n" }.join
  end

  private

  # @rbs source: String
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String?
  def answer(source, theme:, width:)
    body = Riffer::Rig::Terminal::Markdown.render(source, theme: theme, width: width && (width - INDENT))
    body.gsub(/^(?=.)/, ' ' * INDENT).chomp unless body.empty?
  end

  # @rbs stats: Riffer::Rig::Terminal::TurnBuffer::Stats
  # @rbs session: Riffer::Providers::TokenUsage?
  # @rbs return: String
  def footer(stats, session)
    usage = stats.usage
    minutes, seconds = stats.wall_time.to_i.divmod(60)
    [
      "#{stats.steps} #{stats.steps == 1 ? 'step' : 'steps'}",
      format('%<minutes>02d:%<seconds>02d', minutes: minutes, seconds: seconds),
      *([*tokens(usage), *cost(usage)] if usage),
      *(["session #{session.total_tokens} tok", *cost(session)] if session)
    ].join(' · ')
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: Array[String]
  def tokens(usage)
    cache = { cache_write: usage.cache_write_tokens, cache_read: usage.cache_read_tokens }
    [
      "↑#{usage.input_tokens}",
      "↓#{usage.output_tokens}",
      *cache.filter_map { |name, count| "#{name}:#{count}" if count&.positive? }
    ]
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: String?
  def cost(usage)
    amount = usage.cost
    format('~$%.4f', amount) if amount
  end

  # @rbs text: String
  # @rbs width: Integer?
  # @rbs return: String
  def wrap(text, width)
    wrapper = Riffer::Rig::Terminal::Wrapper.new(width: width, indent: INDENT)
    (wrapper << "#{text}\n").chomp
  end
end
