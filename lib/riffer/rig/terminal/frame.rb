# frozen_string_literal: true

require 'io/console'

class Riffer::Rig::Terminal::Frame
  PROMPT = '›' #: String

  PROMPT_COLUMNS = 2 #: Integer

  STATUS_INDENT = '  ' #: String

  # The first column is the cursor's own cell when it rests at the end of the
  # text.
  QUEUED_GAP = '   ' #: String

  # The cursor rests on the input line, the footer's first row, so this wipes
  # the whole footer.
  ERASE = "\r\e[J" #: String

  # @rbs @io: IO
  # @rbs @theme: Riffer::Rig::Terminal::Theme
  # @rbs @editor: Riffer::Rig::Terminal::LineEditor
  # @rbs @status: String
  # @rbs @queued: Integer
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
    @width = 0
    @active = false
    @mutex = Mutex.new
    @previous_resize = nil
  end

  # @rbs return: void
  def start
    @mutex.synchronize do
      width = measure
      return unless width

      @width = width
      @active = true
      write(footer)
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
      write(@active ? "#{ERASE}#{lines.gsub(/\r?\n/, "\r\n")}#{footer}" : lines)
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

  # @rbs return: void
  def stop
    @mutex.synchronize do
      return unless @active

      @active = false
      write(ERASE)
    end
    Signal.trap('WINCH', @previous_resize)
  end

  private

  # @rbs return: void
  def resize
    @mutex.synchronize do
      @width = measure || @width
      redraw
    end
  end

  # winsize raises on ttys with no queryable window size and some pty
  # wrappers report zero columns; a footer that cannot be fitted to the
  # width would wrap and strand the cursor, so neither gets one.
  # @rbs return: Integer?
  def measure
    return nil unless @io.tty?

    width = @io.winsize[1]
    width.positive? ? width : nil
  rescue SystemCallError
    nil
  end

  # @rbs return: void
  def redraw
    write("#{ERASE}#{footer}") if @active
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
    status = Riffer::Rig::Terminal::Columns.head("#{STATUS_INDENT}#{@status}", room)
    column = [PROMPT_COLUMNS + Riffer::Rig::Terminal::Columns.width(before), room].min
    "#{input}\r\n#{status}\e[1A\e[#{column + 1}G"
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

  # @rbs bytes: String
  # @rbs return: void
  def write(bytes)
    @io.print(bytes)
    @io.flush
  end
end
