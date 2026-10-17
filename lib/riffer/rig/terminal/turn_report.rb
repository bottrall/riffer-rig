# frozen_string_literal: true

module Riffer::Rig::Terminal::TurnReport
  extend self

  INDENT = 2 #: Integer

  INTERRUPTED = 'interrupted'

  COLUMN_HEAD = /\A.*\S {2,}(?=\S)/ #: Regexp

  # @rbs turn: Riffer::Rig::Terminal::TurnReport::_Turn
  # @rbs session: Riffer::Providers::TokenUsage?
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String
  def call(turn, session, theme:, width:)
    closing = turn.interrupted? ? INTERRUPTED : footer(turn.stats, session)
    blocks = [*answer(turn.answer, theme: theme, width: width), theme.dim(wrap(closing, width))]
    blocks.map { |block| "\n#{block}\n" }.join
  end

  # @rbs text: String
  # @rbs width: Integer?
  # @rbs return: String
  def wrap(text, width)
    text.lines(chomp: true).map { |line| wrap_line(line, width) }.join("\n")
  end

  private

  # @rbs line: String
  # @rbs width: Integer?
  # @rbs return: String
  def wrap_line(line, width)
    if line.strip.empty?
      ''
    elsif width.nil? || Riffer::Rig::Terminal::Columns.width(line) <= width - INDENT
      "#{' ' * INDENT}#{line}"
    else
      # Wrapping packs words with single spaces, so the columns of a line laid
      # out as a table survive only in a head kept out of the wrap.
      head = column_head(line, width - INDENT)
      indent = INDENT + Riffer::Rig::Terminal::Columns.width(head)
      rows = (Riffer::Rig::Terminal::Wrapper.new(width: width, indent: indent) << "#{line.delete_prefix(head)}\n").chomp
      "#{' ' * INDENT}#{head}#{rows.delete_prefix(' ' * indent)}"
    end
  end

  # @rbs line: String
  # @rbs limit: Integer
  # @rbs return: String
  def column_head(line, limit)
    # Only the first half of the row is searched: a wider head would squeeze
    # the text hung under it to a sliver, and the double spaces of a long
    # detail (indented code in tool arguments) would pass for its columns.
    Riffer::Rig::Terminal::Columns.head(line, (limit / 2) + 1)[COLUMN_HEAD].to_s
  end

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
end
