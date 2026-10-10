# frozen_string_literal: true

class Riffer::Rig::Terminal::Picker
  HEADER = 'Resume a session — type to filter, Enter switches on a single match, Ctrl-D deletes' #: String

  DELETE_HEADER = 'Delete a session — type its number' #: String

  DELETED = 'Deleted.' #: String

  EMPTY = 'No saved sessions.' #: String

  EOT = "\u{4}" #: String

  # @rbs @input: IO
  # @rbs @renderer: Riffer::Rig::Terminal::Renderer
  # @rbs @host: Riffer::Rig::Hosts::_Host
  # @rbs @sessions: Riffer::Rig::Terminal::_Sessions

  # @rbs input: IO
  # @rbs renderer: Riffer::Rig::Terminal::Renderer
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs sessions: Riffer::Rig::Terminal::_Sessions
  # @rbs return: void
  def initialize(input:, renderer:, host:, sessions:)
    @input = input
    @renderer = renderer
    @host = host
    @sessions = sessions
  end

  # @rbs all: bool
  # @rbs return: Riffer::Rig::Terminal::Session?
  def open(all:)
    rows = @sessions.list(@host, all: all)
    if rows.empty?
      @renderer.notice(EMPTY)
      return nil
    end

    filter = ''
    loop do
      shown = rows.filter { |row| matches?(row, filter) }
      @renderer.question(HEADER, shown.map { |row| row_text(row, all) }, false)
      case (line = read)
      when nil, EOT
        outcome = delete_mode(shown, all)
        case outcome
        when :cancel then return nil
        else
          rows = outcome
          if rows.empty?
            @renderer.notice(EMPTY)
            return nil
          end
        end
      when :interrupt
        return nil
      when ''
        return shown.first if shown.one?

        return nil
      else
        choice = number(line, shown)
        return choice if choice

        filter = line
      end
    end
  rescue Interrupt
    nil
  end

  private

  # @rbs row: Riffer::Rig::Terminal::Session
  # @rbs filter: String
  # @rbs return: bool
  def matches?(row, filter)
    filter.empty? || row.title.downcase.include?(filter.downcase)
  end

  # @rbs line: String
  # @rbs shown: Array[Riffer::Rig::Terminal::Session]
  # @rbs return: Riffer::Rig::Terminal::Session?
  def number(line, shown)
    return nil unless line.match?(/\A\d+\z/)

    shown[line.to_i - 1]
  end

  # @rbs shown: Array[Riffer::Rig::Terminal::Session]
  # @rbs all: bool
  # @rbs return: Array[Riffer::Rig::Terminal::Session] | :cancel
  def delete_mode(shown, all)
    @renderer.question(DELETE_HEADER, shown.map { |row| row_text(row, all) }, false)
    line = read
    return :cancel unless line.is_a?(String)

    choice = number(line, shown)
    return shown unless choice
    return shown unless @host.confirm("Delete \"#{choice.title}\"?")

    @sessions.delete(@host, choice.id)
    @renderer.notice(DELETED)
    @sessions.list(@host, all: all)
  end

  # @rbs return: String | :interrupt | nil
  def read
    @input.gets&.strip
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

    span = Time.now - updated
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
