# frozen_string_literal: true

class Riffer::Rig::Terminal::Picker
  HEADER = 'Resume a session — type to filter, Enter switches on a single match, Ctrl-D deletes' #: String

  DELETE_HEADER = 'Delete a session — type its number' #: String

  DELETED = 'Deleted.' #: String

  EMPTY = 'No saved sessions.' #: String

  CLOSED = '(closed)' #: String

  NO_MATCH = 'No sessions match "%s"' #: String

  EOT = "\u{4}" #: String

  # @rbs @prompter: Riffer::Rig::Terminal::_Prompter
  # @rbs @renderer: Riffer::Rig::Terminal::Renderer
  # @rbs @host: Riffer::Rig::Hosts::_Host
  # @rbs @sessions: Riffer::Rig::Terminal::_Sessions
  # @rbs @now: ^() -> Time

  # @rbs prompter: Riffer::Rig::Terminal::_Prompter
  # @rbs renderer: Riffer::Rig::Terminal::Renderer
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs sessions: Riffer::Rig::Terminal::_Sessions
  # @rbs now: ^() -> Time
  # @rbs return: void
  def initialize(prompter:, renderer:, host:, sessions:, now: -> { Time.now })
    @prompter = prompter
    @renderer = renderer
    @host = host
    @sessions = sessions
    @now = now
  end

  # @rbs all: bool
  # @rbs return: Riffer::Rig::Terminal::Session?
  def open(all:)
    rows = @sessions.list(@host, all: all)
    if rows.empty?
      @renderer.notice(@sessions.off || EMPTY)
      return nil
    end

    filter = ''
    loop do
      shown = rows.filter { |row| matches?(row, filter) }
      case (line = read(HEADER, shown, all))
      when nil, EOT
        outcome = delete_mode(rows, shown, all)
        case outcome
        when :cancel then return closed
        else
          rows = outcome
          if rows.empty?
            @renderer.notice(EMPTY)
            return nil
          end
          filter = '' unless any_match?(rows, filter)
        end
      when :interrupt
        return closed
      when ''
        return shown.first if shown.one?

        return closed
      else
        choice = number(line, shown)
        return choice if choice

        if any_match?(rows, line)
          filter = line
        else
          @renderer.notice(format(NO_MATCH, line))
        end
      end
    end
  rescue Interrupt
    closed
  end

  private

  # @rbs return: nil
  def closed
    @renderer.notice(CLOSED)
    nil
  end

  # @rbs row: Riffer::Rig::Terminal::Session
  # @rbs filter: String
  # @rbs return: bool
  def matches?(row, filter)
    filter.empty? || row.title.downcase.include?(filter.downcase)
  end

  # @rbs rows: Array[Riffer::Rig::Terminal::Session]
  # @rbs filter: String
  # @rbs return: bool
  def any_match?(rows, filter)
    rows.any? { |row| matches?(row, filter) }
  end

  # @rbs line: String
  # @rbs shown: Array[Riffer::Rig::Terminal::Session]
  # @rbs return: Riffer::Rig::Terminal::Session?
  def number(line, shown)
    return nil unless line.match?(/\A\d+\z/)

    index = line.to_i
    shown[index - 1] if index.positive?
  end

  # @rbs rows: Array[Riffer::Rig::Terminal::Session]
  # @rbs shown: Array[Riffer::Rig::Terminal::Session]
  # @rbs all: bool
  # @rbs return: Array[Riffer::Rig::Terminal::Session] | :cancel
  def delete_mode(rows, shown, all)
    line = read(DELETE_HEADER, shown, all)
    return :cancel unless line.is_a?(String)

    choice = number(line, shown)
    return rows unless choice
    return rows unless @host.confirm("Delete \"#{choice.title}\"?")

    @sessions.delete(@host, choice.id)
    @renderer.notice(DELETED)
    @sessions.list(@host, all: all)
  end

  # @rbs header: String
  # @rbs shown: Array[Riffer::Rig::Terminal::Session]
  # @rbs all: bool
  # @rbs return: String | :interrupt | nil
  def read(header, shown, all)
    @prompter.ask(header, options: shown.map { |row| row_text(row, all) }, secret: false)&.strip
  rescue Interrupt
    :interrupt
  end

  # @rbs row: Riffer::Rig::Terminal::Session
  # @rbs all: bool
  # @rbs return: String
  def row_text(row, all)
    place = all ? "[#{File.basename(row.cwd)}] " : ''
    "#{place}#{row.title} — #{relative(row.updated)}"
  end

  # @rbs updated: Time?
  # @rbs return: String
  def relative(updated)
    return 'unknown' unless updated

    span = @now.call - updated
    case span
    when 0...60 then 'just now'
    when 60...3_600 then "#{count(span.div(60), 'minute')} ago"
    when 3_600...86_400 then "#{count(span.div(3_600), 'hour')} ago"
    when 86_400...2_592_000 then "#{count(span.div(86_400), 'day')} ago"
    else updated.strftime('%b %-d, %Y')
    end
  end

  # @rbs amount: Integer
  # @rbs unit: String
  # @rbs return: String
  def count(amount, unit)
    "#{amount} #{unit}#{'s' unless amount == 1}"
  end
end
