# frozen_string_literal: true

module Riffer::Rig::Terminal::TurnReport
  extend self

  INDENT = 2 #: Integer

  INTERRUPTED = 'interrupted'

  COLUMN_HEAD = /\A.*\S {2,}(?=\S)/ #: Regexp

  VISIBLE = /\S/ #: Regexp

  # @rbs turn: Riffer::Rig::Terminal::TurnReport::_Turn
  # @rbs session: Riffer::Providers::TokenUsage?
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String
  def call(turn, session, theme:, width:)
    closing =
      if turn.interrupted?
        theme.dim(wrap(INTERRUPTED, width))
      else
        footer(turn.stats, session, theme: theme, width: width)
      end
    blocks = [*answer(turn.answer, theme: theme, width: width), closing]
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
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs width: Integer?
  # @rbs return: String
  def footer(stats, session, theme:, width:)
    parts = segments(stats, session)
    paint(wrap(parts.map(&:first).join(' · '), width), owners(parts), theme)
  end

  # @rbs stats: Riffer::Rig::Terminal::TurnBuffer::Stats
  # @rbs session: Riffer::Providers::TokenUsage?
  # @rbs return: Array[[String, Symbol]]
  def segments(stats, session)
    usage = stats.usage
    minutes, seconds = stats.wall_time.to_i.divmod(60)
    [
      ["#{stats.steps} #{stats.steps == 1 ? 'step' : 'steps'}", :dim],
      [format('%<minutes>02d:%<seconds>02d', minutes: minutes, seconds: seconds), :dim],
      *usage_segments(usage),
      *session_segments(session)
    ]
  end

  # @rbs usage: Riffer::Providers::TokenUsage?
  # @rbs return: Array[[String, Symbol]]
  def usage_segments(usage)
    return [] unless usage

    [*tokens(usage), *cost(usage)]
  end

  # @rbs session: Riffer::Providers::TokenUsage?
  # @rbs return: Array[[String, Symbol]]
  def session_segments(session)
    return [] unless session

    [["session #{Riffer::Rig::Terminal::Count.call(session.total_tokens)} tok", :dim], *cost(session)]
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: Array[[String, Symbol]]
  def tokens(usage)
    cache = { cache_write: usage.cache_write_tokens, cache_read: usage.cache_read_tokens }
    [
      ["↑#{Riffer::Rig::Terminal::Count.call(usage.input_tokens)}", :dim],
      ["↓#{Riffer::Rig::Terminal::Count.call(usage.output_tokens)}", :dim],
      *cache.filter_map do |name, count|
        ["#{name}:#{Riffer::Rig::Terminal::Count.call(count)}", :dim] if count&.positive?
      end
    ]
  end

  # @rbs usage: Riffer::Providers::TokenUsage
  # @rbs return: Array[[String, Symbol]]
  def cost(usage)
    amount = usage.cost
    amount ? [[format('~$%.4f', amount), :cyan]] : []
  end

  # A separator's dot is dim, so a colour run carries across it into the next
  # segment.
  # @rbs parts: Array[[String, Symbol]]
  # @rbs return: Array[Symbol]
  def owners(parts)
    parts.flat_map.with_index do |(text, role), index|
      owned = [role] * text.scan(VISIBLE).size
      owned << :dim unless index == parts.length - 1
      owned
    end
  end

  # The Wrapper moves, drops and rewrites whitespace but never a visible
  # character, so the nth visible character of a wrapped line is the nth one
  # the segments supplied — which is why the colours are painted after the
  # wrap, where a span can never be cut in two.
  # @rbs line: String
  # @rbs owners: Array[Symbol]
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: String
  def paint(line, owners, theme)
    chars = line.chars
    owner_at = chars.each_index.select { |index| chars.fetch(index).match?(VISIBLE) }.zip(owners).to_h
    slots = chars.each_index.map { |index| owner_at[index] }
    cells = nearest(slots).zip(nearest(slots.reverse).reverse).map { |left, right| left == right ? left : nil }
    runs = cells.zip(chars).chunk_while { |(left, _), (right, _)| left == right }
    runs.map { |run| color(run.map(&:last).join, run.fetch(0).first, theme) }.join
  end

  # @rbs slots: Array[Symbol?]
  # @rbs return: Array[Symbol?]
  def nearest(slots)
    slots.each_with_object([]) { |slot, filled| filled << (slot || filled.last) }
  end

  # @rbs text: String
  # @rbs role: Symbol?
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs return: String
  def color(text, role, theme)
    case role
    when :dim then theme.dim(text)
    when :cyan then theme.cyan(text)
    else text
    end
  end
end
