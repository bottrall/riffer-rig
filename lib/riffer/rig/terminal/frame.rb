# frozen_string_literal: true

require 'io/console'

class Riffer::Rig::Terminal::Frame
  PROMPT = '›' #: String

  PROMPT_COLUMNS = 2 #: Integer

  STATUS_INDENT = '  ' #: String

  # The first column is the cursor's own cell when it rests at the end of the
  # text.
  QUEUED_GAP = '   ' #: String

  JOBS_SEPARATOR = ' · ' #: String

  FOOTER_ROWS = 2 #: Integer

  PEEK_ROWS = 8 #: Integer

  # The cursor rests on the input line, the footer's first row, so this wipes
  # the whole footer.
  ERASE = "\r\e[J" #: String

  # @rbs @io: IO
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @editor: Riffer::Rig::Terminal::LineEditor
  # @rbs @status: String
  # @rbs @queued: Integer
  # @rbs @jobs: Integer
  # @rbs @peek: String
  # @rbs @peek_height: Integer
  # @rbs @height: Integer
  # @rbs @width: Integer
  # @rbs @active: bool
  # @rbs @mutex: Mutex
  # @rbs @previous_resize: Signal::trap_command

  # @rbs io: IO
  # @rbs theme: Riffer::Rig::Terminal::Theme
  # @rbs editor: Riffer::Rig::Terminal::LineEditor
  # @rbs return: void
  def initialize(io:, theme:, editor: Riffer::Rig::Terminal::LineEditor.new)
    @io = io
    @theme = theme
    @editor = editor
    @status = ''
    @queued = 0
    @jobs = 0
    @peek = ''
    @peek_height = 0
    @height = 0
    @width = 0
    @active = false
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
      write(erase)
    end
    Signal.trap('WINCH', @previous_resize)
  end

  # winsize raises on ttys with no queryable window size and some pty
  # wrappers report zero columns; a footer that cannot be fitted to the
  # width would wrap and strand the cursor, so neither gets one.
  # @rbs return: [Integer, Integer]?
  def measure
    return nil unless @io.tty?

    size = @io.winsize
    size[1].positive? ? size : nil
  rescue SystemCallError
    nil
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
    @peek_height.zero? ? ERASE : "\e[#{@peek_height}A#{ERASE}"
  end

  # @rbs before: String
  # @rbs return: void
  def draw(before = '')
    rows = peek_rows
    write("#{before}#{rows.join}#{footer}")
    @peek_height = rows.size
  end

  # @rbs return: Array[String]
  def peek_rows
    room = @width - 1
    # A row scrolled off the top of the screen could never be erased again.
    limit = (@height - FOOTER_ROWS).clamp(0, PEEK_ROWS)
    wrapper = Riffer::Rig::Terminal::Wrapper.new(width: room, indent: STATUS_INDENT.size)
    # Every line fills at least one row, so the rows shown come from the last
    # few lines; wrapping only those keeps a redraw from growing with the peek.
    tail = @peek.lines.last(limit).join
    "#{wrapper << tail}#{wrapper.flush}".lines(chomp: true).last(limit).map do |row|
      "#{@theme.dim(Riffer::Rig::Terminal::Columns.head(row, room))}\r\n"
    end
  end

  # @rbs return: String
  def footer
    # The last column stays empty: a glyph written there leaves the cursor
    # in a pending wrap, which terminals resolve differently.
    room = @width - 1
    typing = [room - PROMPT_COLUMNS, 0].max
    before = Riffer::Rig::Terminal::Columns.tail(@editor.printable_before, typing)
    after = Riffer::Rig::Terminal::Columns.head(
      @editor.printable_after,
      typing - Riffer::Rig::Terminal::Columns.width(before)
    )
    typed = "#{before}#{after}"
    spare = typing - Riffer::Rig::Terminal::Columns.width(typed)
    input = Riffer::Rig::Terminal::Columns.head("#{@theme.pink(PROMPT)} #{typed}#{chip(spare)}", room)
    column = [PROMPT_COLUMNS + Riffer::Rig::Terminal::Columns.width(before), room].min
    "#{input}\r\n#{status_line(room)}\e[1A\e[#{column + 1}G"
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
    label = counter(room)
    return Riffer::Rig::Terminal::Columns.head("#{STATUS_INDENT}#{@status}", room) unless label

    # The counter is the only sign that a job is still running, so the status
    # is the one cut to make room.
    status = Riffer::Rig::Terminal::Columns.head(@status, status_columns(room))
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
