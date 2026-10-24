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
    return empty(@sessions.off || EMPTY) if rows.empty?

    listing = Listing.new(rows: rows)
    loop do
      step = handle(listing, all)
      return step unless step.is_a?(Listing)

      listing = step
    end
  rescue Interrupt
    closed
  end

  private

  # @rbs listing: Riffer::Rig::Terminal::Picker::Listing
  # @rbs all: bool
  # @rbs return: Riffer::Rig::Terminal::Picker::Listing | Riffer::Rig::Terminal::Session | nil
  def handle(listing, all)
    shown = listing.shown
    case (line = read(HEADER, shown, all))
    when nil, EOT then delete_mode(listing, shown, all)
    when :interrupt then closed
    when '' then shown.one? ? shown.first : closed
    else number(line, shown) || narrow(listing, line)
    end
  end

  # @rbs listing: Riffer::Rig::Terminal::Picker::Listing
  # @rbs filter: String
  # @rbs return: Riffer::Rig::Terminal::Picker::Listing
  def narrow(listing, filter)
    return listing.narrow(filter) if listing.any_match?(filter)

    @renderer.notice(format(NO_MATCH, filter))
    listing
  end

  # @rbs listing: Riffer::Rig::Terminal::Picker::Listing
  # @rbs shown: Array[Riffer::Rig::Terminal::Session]
  # @rbs all: bool
  # @rbs return: Riffer::Rig::Terminal::Picker::Listing?
  def delete_mode(listing, shown, all)
    line = read(DELETE_HEADER, shown, all)
    return closed unless line.is_a?(String)

    rows = delete(number(line, shown), all) || listing.rows
    return empty(EMPTY) if rows.empty?

    listing.relist(rows)
  end

  # @rbs choice: Riffer::Rig::Terminal::Session?
  # @rbs all: bool
  # @rbs return: Array[Riffer::Rig::Terminal::Session]?
  def delete(choice, all)
    return nil unless choice && @host.confirm("Delete \"#{choice.title}\"?")

    @sessions.delete(@host, choice.id)
    @renderer.notice(DELETED)
    @sessions.list(@host, all: all)
  end

  # @rbs message: String
  # @rbs return: nil
  def empty(message)
    @renderer.notice(message)
    nil
  end

  # @rbs return: nil
  def closed
    @renderer.notice(CLOSED)
    nil
  end

  # @rbs line: String
  # @rbs shown: Array[Riffer::Rig::Terminal::Session]
  # @rbs return: Riffer::Rig::Terminal::Session?
  def number(line, shown)
    return nil unless line.match?(/\A\d+\z/)

    index = line.to_i
    shown[index - 1] if index.positive?
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
