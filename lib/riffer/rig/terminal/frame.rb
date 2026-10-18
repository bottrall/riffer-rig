# frozen_string_literal: true

require 'io/console'

class Riffer::Rig::Terminal::Frame
  PROMPT = '›' #: String

  PROMPT_COLUMNS = 2 #: Integer

  INDENT = ' ' * PROMPT_COLUMNS #: String

  STATUS_INDENT = '  ' #: String

  # The first column is the cursor's own cell when it rests at the end of the
  # text.
  QUEUED_GAP = '   ' #: String

  JOBS_SEPARATOR = ' · ' #: String

  INPUT_ROWS = 8 #: Integer

  PEEK_ROWS = 8 #: Integer

  PALETTE_ROWS = 8 #: Integer

  SELECTED = '▸' #: String

  DESCRIPTION_GAP = '  ' #: String

  # Sent from the top row the frame drew, so this wipes all of it.
  ERASE = "\r\e[J" #: String

  LOADING = 'loading…' #: String

  SPACER = "\r\n" #: String

  # Marks the cursor's cell in the text handed to the wrapper, so the wrapped
  # row and column can be read back off it: a private-use code point, which no
  # terminal draws.
  CURSOR = "\uE000" #: String

  # @rbs @io: IO
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @editor: Riffer::Rig::Terminal::LineEditor
  # @rbs @completion: Riffer::Rig::Terminal::Autocomplete?
  # @rbs @status: String
  # @rbs @hint: String?
  # @rbs @queued: Integer
  # @rbs @jobs: Integer
  # @rbs @peek: String
  # @rbs @rows_above: Integer
  # @rbs @height: Integer
  # @rbs @width: Integer
  # @rbs @active: bool
  # @rbs @loading: bool
  # @rbs @loading_line: String
  # @rbs @mutex: Mutex
  # @rbs @previous_resize: Signal::trap_command

  # winsize raises on ttys with no queryable window size and some pty
  # wrappers report zero columns; output that cannot be fitted to the width
  # would wrap mid-line (and strand a footer's cursor), so neither gets one.
  # @rbs io: IO
  # @rbs return: [Integer, Integer]?
  def self.measure(io)
    return nil unless io.tty?

    size = io.winsize
    size[1].positive? ? size : nil
  rescue SystemCallError
    nil
  end

  # @rbs io: IO
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs editor: Riffer::Rig::Terminal::LineEditor
  # @rbs loading: bool
  # @rbs return: void
  def initialize(io:, theme:, editor: Riffer::Rig::Terminal::LineEditor.new, loading: false)
    @io = io
    @theme = theme
    @editor = editor
    @completion = nil
    @status = ''
    @hint = nil
    @queued = 0
    @jobs = 0
    @peek = ''
    @rows_above = 0
    @height = 0
    @width = 0
    @active = false
    @loading = loading
    @loading_line = LOADING
    @mutex = Mutex.new
    @previous_resize = nil
  end

  # @rbs return: void
  def start
    @mutex.synchronize do
      size = measure
      return unless size

      @height, @width = size
      @active = true
      draw
    end
    # A trap handler may not take the mutex, so it hands the resize to a thread.
    @previous_resize = Signal.trap('WINCH') { Thread.new { resize } }
  end

  # @rbs content: String
  # @rbs return: void
  def append(content)
    lines = content.end_with?("\n") ? content : "#{content}\n"
    @mutex.synchronize do
      # The first content and the footer it draws go out in this one write, so
      # this is where the loading screen ends.
      @loading = false
      # The key pipeline's raw mode turns off output post-processing, so a
      # bare line feed would not return the carriage.
      @active ? draw("#{erase}#{lines.gsub(/\r?\n/, "\r\n")}") : write(lines)
    end
  end

  # @rbs editor: Riffer::Rig::Terminal::LineEditor
  # @rbs return: void
  def input(editor)
    @mutex.synchronize do
      @editor = editor
      @completion = nil
      redraw
    end
  end

  # @rbs completion: Riffer::Rig::Terminal::Autocomplete
  # @rbs return: void
  def complete(completion)
    @mutex.synchronize do
      @editor = completion.editor
      @completion = completion
      redraw
    end
  end

  # @rbs status: String
  # @rbs return: void
  def status(status)
    @mutex.synchronize do
      @status = status
      redraw
    end
  end

  # @rbs line: String
  # @rbs return: void
  def loading(line)
    @mutex.synchronize do
      @loading_line = line
      # A tick still in flight once the banner drew would otherwise redraw the
      # footer under it.
      redraw if @loading
    end
  end

  # @rbs return: bool
  def loading?
    @mutex.synchronize { @loading }
  end

  # @rbs hint: String?
  # @rbs return: void
  def hint(hint)
    @mutex.synchronize do
      @hint = hint
      redraw
    end
  end

  # @rbs count: Integer
  # @rbs return: void
  def queued(count)
    @mutex.synchronize do
      @queued = count
      redraw
    end
  end

  # @rbs count: Integer
  # @rbs return: void
  def jobs(count)
    @mutex.synchronize do
      @jobs = count
      redraw
    end
  end

  # @rbs return: Integer
  def status_room
    @mutex.synchronize { [status_columns(@width - 1), 0].max }
  end

  # @rbs content: String
  # @rbs return: void
  def peek(content)
    @mutex.synchronize do
      @peek = content
      redraw
    end
  end

  # @rbs return: void
  def stop
    @mutex.synchronize do
      return unless @active

      @active = false
      # Ends the loading animation's thread, which stops itself from its next
      # tick once the row it draws is gone.
      @loading = false
      write(erase)
    end
    Signal.trap('WINCH', @previous_resize)
  end

  # @rbs return: [Integer, Integer]?
  def measure
    self.class.measure(@io)
  end

  private

  # @rbs return: void
  def resize
    @mutex.synchronize do
      @height, @width = measure || [@height, @width]
      redraw
    end
  end

  # @rbs return: void
  def redraw
    draw(erase) if @active
  end

  # @rbs return: String
  def erase
    @rows_above.zero? ? ERASE : "\e[#{@rows_above}A#{ERASE}"
  end

  # @rbs before: String
  # @rbs return: void
  def draw(before = '')
    return draw_loading(before) if @loading

    shown, row, column = input_rows
    # A row scrolled off the top of the screen could never be erased again.
    # The status sits under the input and the spacer above everything drawn.
    above = [@height - shown.size - 2, 0].max
    palette = palette_rows([above, PALETTE_ROWS].min)
    spacer = SPACER if @height >= shown.size + 2
    lead = [*spacer, *peek_rows([above - palette.size, PEEK_ROWS].min), *palette]
    write("#{before}#{lead.join}#{footer(shown, row, column)}")
    @rows_above = lead.size + row
  end

  # The cursor stays on the row the loading line was written to, so the erase
  # that replaces it wipes it like the footer's own row.
  # @rbs before: String
  # @rbs return: void
  def draw_loading(before)
    line = "#{STATUS_INDENT}#{@theme.dim(@loading_line)}"
    write("#{before}#{Riffer::Rig::Terminal::Columns.head(line, @width - 1)}")
  end

  # @rbs limit: Integer
  # @rbs return: Array[String]
  def peek_rows(limit)
    room = @width - 1
    wrapper = Riffer::Rig::Terminal::Wrapper.new(width: room, indent: STATUS_INDENT.size)
    # Every line fills at least one row, so the rows shown come from the last
    # few lines; wrapping only those keeps a redraw from growing with the peek.
    tail = @peek.lines.last(limit).join
    "#{wrapper << tail}#{wrapper.flush}".lines(chomp: true).last(limit).map do |row|
      "#{@theme.dim(Riffer::Rig::Terminal::Columns.head(row, room))}\r\n"
    end
  end

  # @rbs limit: Integer
  # @rbs return: Array[String]
  def palette_rows(limit)
    completion = @completion
    return [] unless completion

    first = [completion.index - limit + 1, 0].max
    shown = completion.matches.drop(first).first(limit)
    width = Riffer::Rig::Terminal::Help.width(shown)
    shown.each_with_index.map do |command, offset|
      palette_row(command, width, chosen: first + offset == completion.index)
    end
  end

  # @rbs command: Riffer::Rig::Terminal::Autocomplete::_Entry
  # @rbs width: Integer
  # @rbs chosen: bool
  # @rbs return: String
  def palette_row(command, width, chosen:)
    name = Riffer::Rig::Terminal::Help.label(command, width)
    about = Riffer::Rig::Terminal::Help.about(command)
    label = chosen ? "#{SELECTED} #{@theme.pink(name)}" : "#{STATUS_INDENT}#{name}"
    "#{Riffer::Rig::Terminal::Columns.head("#{label}#{DESCRIPTION_GAP}#{@theme.dim(about)}", @width - 1)}\r\n"
  end

  # The input rows as drawn, the row the cursor sits on among them, and its
  # column on that row.
  # @rbs return: [Array[String], Integer, Integer]
  def input_rows
    return viewport if typing < 1

    # The last column stays empty: a glyph written there leaves the cursor
    # in a pending wrap, which terminals resolve differently.
    # The echo shows the text Enter will send, so its spaces are never folded.
    wrapper = Riffer::Rig::Terminal::Wrapper.new(width: @width - 1, indent: PROMPT_COLUMNS, verbatim: true)
    wrapped = "#{wrapper << "#{@editor.printable_before}#{CURSOR}#{@editor.printable_after}"}#{wrapper.flush}"
    rows = wrapped.lines(chomp: true)
    row = rows.index { |line| line.include?(CURSOR) } || 0
    prefix = rows.fetch(row).partition(CURSOR).first.delete_prefix(INDENT)
    column = PROMPT_COLUMNS + Riffer::Rig::Terminal::Columns.width(prefix)

    first = (rows.size - input_cap).clamp(0, row)
    shown = rows.drop(first).take(input_cap).map do |line|
      line.delete_prefix(INDENT).sub(CURSOR, '')
    end
    row -= first
    shown[row] = ghosted(shown.fetch(row))
    last = shown.last
    shown[-1] = "#{last}#{chip(typing - Riffer::Rig::Terminal::Columns.width(last))}"
    prompted = shown.each_with_index.map do |line, offset|
      if (first + offset).zero?
        "#{@theme.pink(PROMPT)} #{line}"
      else
        "#{INDENT}#{line}"
      end
    end
    [prompted, row, column]
  end

  # @rbs return: Integer
  def input_cap
    (@height - 1).clamp(1, INPUT_ROWS)
  end

  # @rbs line: String
  # @rbs return: String
  def ghosted(line)
    ghost = Riffer::Rig::Terminal::Columns.head(
      @completion&.ghost.to_s,
      typing - Riffer::Rig::Terminal::Columns.width(line)
    )
    "#{line}#{@theme.dim(ghost) unless ghost.empty?}"
  end

  # @rbs return: Integer
  def typing
    @width - 1 - PROMPT_COLUMNS
  end

  # The wrapped rows need a column for the prompt and one of text; on a
  # narrower terminal the input stays the one-row viewport, cut to fit.
  # @rbs return: [Array[String], Integer, Integer]
  def viewport
    room = @width - 1
    [[Riffer::Rig::Terminal::Columns.head("#{@theme.pink(PROMPT)} ", room)], 0, room]
  end

  # @rbs rows: Array[String]
  # @rbs row: Integer
  # @rbs column: Integer
  # @rbs return: String
  def footer(rows, row, column)
    "#{rows.join("\r\n")}\r\n#{status_line(@width - 1)}\e[#{rows.size - row}A\e[#{column + 1}G"
  end

  # @rbs room: Integer
  # @rbs return: String
  def chip(room)
    label = "· #{@queued} queued"
    # A count cut short would read as a smaller queue, so the chip is drawn
    # whole or not at all.
    return '' if @queued.zero? || QUEUED_GAP.size + label.size > room

    "#{QUEUED_GAP}#{@theme.dim(label)}"
  end

  # @rbs room: Integer
  # @rbs return: String
  def status_line(room)
    # A running ticker sets the status on every tick, so a hint outranks it
    # rather than being drawn over.
    shown = @hint || @status
    label = counter(room)
    return Riffer::Rig::Terminal::Columns.head("#{STATUS_INDENT}#{shown}", room) unless label

    # The counter is the only sign that a job is still running, so the status
    # is the one cut to make room.
    status = Riffer::Rig::Terminal::Columns.head(shown, status_columns(room))
    # A status cut to nothing still carries its styles.
    trailer = Riffer::Rig::Terminal::Columns.width(status).zero? ? label : "#{JOBS_SEPARATOR}#{label}"
    "#{STATUS_INDENT}#{status}#{@theme.dim(trailer)}"
  end

  # @rbs room: Integer
  # @rbs return: Integer
  def status_columns(room)
    label = counter(room)
    room - STATUS_INDENT.size - (label ? JOBS_SEPARATOR.size + label.size : 0)
  end

  # @rbs room: Integer
  # @rbs return: String?
  def counter(room)
    label = "#{@jobs} #{@jobs == 1 ? 'job' : 'jobs'} running"
    # A count cut short would read as fewer jobs, so the counter is drawn
    # whole or not at all.
    label unless @jobs.zero? || STATUS_INDENT.size + label.size > room
  end

  # @rbs bytes: String
  # @rbs return: void
  def write(bytes)
    @io.print(bytes)
    @io.flush
  end
end
