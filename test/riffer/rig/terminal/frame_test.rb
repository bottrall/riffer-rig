# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require_relative '../../../support/frame_pty'

describe Riffer::Rig::Terminal::Frame do
  def empty_footer = "› \r\n  \e[1A\e[3G"

  def empty_frame = "\r\n#{empty_footer}"

  def teardown
    @frame&.stop
    @pty&.close
  end

  def tty(columns, rows: 24)
    io = StringIO.new
    io.define_singleton_method(:tty?) { true }
    io.define_singleton_method(:winsize) { [rows, columns] }
    io
  end

  def frame(io, color: false, editor: Riffer::Rig::Terminal::LineEditor.new, loading: false)
    theme = Riffer::Rig::Terminal::Theme.new(enabled: color)
    @frame = Riffer::Rig::Terminal::Frame.new(io: io, theme: theme, editor: editor, loading: loading)
  end

  def started(io, **)
    frame(io, **).tap(&:start)
  end

  def started_loading(io, line)
    frame = frame(io, loading: true)
    frame.loading(line)
    frame.start
    frame
  end

  def on_pty(columns: 40, rows: 6)
    @pty = FramePty.new(columns: columns, rows: rows)
    started(@pty.slave)
  end

  def editing(before, after = '')
    Riffer::Rig::Terminal::LineEditor.new(before: before, after: after)
  end

  def commands(described = { 'auth' => 'Store credentials', 'model' => 'Switch the model' })
    described.map { |name, about| Riffer::Rig::Command.new(name, description: about, extension: :core) { nil } }
  end

  def completing(*keys, listed: commands)
    keys.reduce(Riffer::Rig::Terminal::Autocomplete.new(commands: listed)) do |state, key|
      state.press(key.is_a?(String) ? Riffer::Rig::Terminal::Key.new(:text, key) : Riffer::Rig::Terminal::Key.new(key))
    end
  end

  def palette = "▸ /auth   Store credentials\r\n  /model  Switch the model\r\n"

  describe '.measure' do
    it 'is nil when the io is not a tty' do
      assert_nil Riffer::Rig::Terminal::Frame.measure(StringIO.new)
    end

    it 'is the rows and columns of the tty' do
      assert_equal [24, 80], Riffer::Rig::Terminal::Frame.measure(tty(80))
    end

    it 'is nil when the tty reports zero columns' do
      assert_nil Riffer::Rig::Terminal::Frame.measure(tty(0))
    end

    it 'is nil when the window size cannot be queried' do
      io = tty(80)
      io.define_singleton_method(:winsize) { raise Errno::ENOTTY }

      assert_nil Riffer::Rig::Terminal::Frame.measure(io)
    end
  end

  describe '#start' do
    it 'draws no footer when the terminal cannot be measured' do
      io = StringIO.new

      started(io)

      assert_equal '', io.string
    end

    it 'draws a blank row, the input line and the status line, and rests the cursor after the prompt' do
      io = tty(80)

      started(io)

      assert_equal empty_frame, io.string
    end

    it 'draws no blank row on a terminal with no row to spare for it' do
      io = tty(80, rows: 2)

      started(io)

      assert_equal empty_footer, io.string
    end

    it 'paints the prompt when color is on' do
      io = tty(80)

      started(io, color: true)

      assert_equal "\r\n\e[38;2;255;106;193m›\e[0m \r\n  \e[1A\e[3G", io.string
    end

    it 'draws the editor it was built with' do
      io = tty(80)

      started(io, editor: editing('hi'))

      assert_equal "\r\n› hi\r\n  \e[1A\e[5G", io.string
    end

    it 'draws the peek it was given before it started under the blank row' do
      io = tty(80)
      unstarted = frame(io)
      unstarted.peek('thinking')

      unstarted.start

      assert_equal "\r\n  thinking\r\n#{empty_footer}", io.string
    end

    it 'draws the loading line in place of the input row when it starts loading' do
      io = tty(80)

      started(io, loading: true)

      assert_equal '  loading…', io.string
    end

    it 'draws the loading line it was pushed in place of the input row' do
      io = tty(80)

      started_loading(io, '⠙ warming the amp…')

      assert_equal '  ⠙ warming the amp…', io.string
    end

    it 'cuts the loading line it was pushed to the width of the terminal' do
      io = tty(10)

      started_loading(io, '⠙ warming the amp…')

      assert_equal '  ⠙ warmi', io.string
    end
  end

  describe '#append' do
    it 'prints the content alone when there is no footer' do
      io = StringIO.new

      started(io).append("one\ntwo\n")

      assert_equal "one\ntwo\n", io.string
    end

    it 'ends unterminated content with a newline' do
      io = StringIO.new

      started(io).append('one')

      assert_equal "one\n", io.string
    end

    it 'replaces the frame with the content from its blank row and redraws it below' do
      io = tty(80)

      started(io).append('one')

      assert_equal "#{empty_frame}\e[1A\r\e[Jone\r\n#{empty_frame}", io.string
    end

    it 'swaps the loading line for the content and the input row in one write' do
      io = tty(80)

      started(io, loading: true).append('one')

      assert_equal "  loading…\r\e[Jone\r\n#{empty_frame}", io.string
    end

    it 'swaps a pushed loading line for the content and the input row in one write' do
      io = tty(80)

      started_loading(io, '⠙ warming the amp…').append('one')

      assert_equal "  ⠙ warming the amp…\r\e[Jone\r\n#{empty_frame}", io.string
    end

    it 'draws nothing for a loading line pushed after the first content' do
      io = tty(80)
      frame = started_loading(io, '⠙ warming the amp…')
      frame.append('one')

      frame.loading('⠹ rolling the tape…')

      assert_equal "  ⠙ warming the amp…\r\e[Jone\r\n#{empty_frame}", io.string
    end

    it 'replaces the footer with the content on a terminal with no row to spare for a blank row' do
      io = tty(80, rows: 2)

      started(io).append('one')

      assert_equal "#{empty_footer}\r\e[Jone\r\n#{empty_footer}", io.string
    end

    it 'returns the carriage after every line of the content' do
      io = tty(80)

      started(io).append("one\ntwo\r\n")

      assert_includes io.string, "\e[Jone\r\ntwo\r\n\r\n›"
    end

    it 'prints the content above the peek' do
      io = tty(80)
      frame = started(io)
      frame.peek('thinking')

      frame.append('one')

      assert_operator io.string, :end_with?, "\e[2A\r\e[Jone\r\n\r\n  thinking\r\n#{empty_footer}"
    end

    it 'keeps content above the footer when prints interleave with redraws' do
      frame = on_pty(rows: 30)

      [
        Thread.new { 20.times { |n| frame.append("line #{n}") } },
        Thread.new { 20.times { |n| frame.status("tick #{n}") } },
        Thread.new { 20.times { |n| frame.input(editing('x' * n)) } }
      ].each(&:join)

      assert_equal [*Array.new(20) { |n| "line #{n}" }, '', "› #{'x' * 19}", '  tick 19'], @pty.screen.rows
    end

    it 'keeps the frame on the last rows once the content scrolls' do
      frame = on_pty(rows: 5)

      5.times { |n| frame.append("line #{n}") }

      assert_equal ['line 3', 'line 4', '', '›', ''], @pty.screen.rows
    end

    it 'leaves the cursor on the input line' do
      frame = on_pty

      frame.append("one\ntwo")

      assert_equal [3, 2], [@pty.screen.row, @pty.screen.column]
    end
  end

  describe '#input' do
    it 'draws nothing when there is no footer' do
      io = StringIO.new

      started(io).input(editing('hi'))

      assert_equal '', io.string
    end

    it 'redraws the footer with the cursor between the text either side of it' do
      io = tty(80)

      started(io).input(editing('hi', 'yo'))

      assert_equal "#{empty_frame}\e[1A\r\e[J\r\n› hiyo\r\n  \e[1A\e[5G", io.string
    end

    it 'leaves the cursor at the edit point' do
      frame = on_pty

      frame.input(editing('hi', 'yo'))

      assert_equal [1, 4], [@pty.screen.row, @pty.screen.column]
    end

    it 'erases the palette of an earlier completion' do
      io = tty(80)
      frame = started(io)
      frame.complete(completing('/'))

      frame.input(editing('hi'))

      assert_operator io.string, :end_with?, "\e[3A\r\e[J\r\n› hi\r\n  \e[1A\e[5G"
    end

    it 'keeps the loading line over an edit made before the first content' do
      io = tty(80)

      started(io, loading: true).input(editing('hi'))

      assert_equal "  loading…\r\e[J  loading…", io.string
    end

    it 'keeps the pushed loading line over an edit made before the first content' do
      io = tty(80)

      started_loading(io, '⠙ warming the amp…').input(editing('hi'))

      assert_equal "  ⠙ warming the amp…\r\e[J  ⠙ warming the amp…", io.string
    end

    it 'redraws the loading row when another line is pushed while it loads' do
      io = tty(80)

      started_loading(io, '⠙ warming the amp…').loading('⠸ checking the levels…')

      assert_equal "  ⠙ warming the amp…\r\e[J  ⠸ checking the levels…", io.string
    end

    it 'shows an edit typed while loading once the first content draws the input row' do
      io = tty(80)
      frame = started(io, loading: true)
      frame.input(editing('hi'))

      frame.append('banner')

      assert_operator io.string, :end_with?, "banner\r\n\r\n› hi\r\n  \e[1A\e[5G"
    end
  end

  describe '#complete' do
    it 'draws nothing when there is no footer' do
      io = StringIO.new

      started(io).complete(completing('/'))

      assert_equal '', io.string
    end

    it 'redraws the footer under the palette of the completion' do
      io = tty(80)

      started(io).complete(completing('/'))

      assert_equal "#{empty_frame}\e[1A\r\e[J\r\n#{palette}› /auth\r\n  \e[1A\e[4G", io.string
    end

    it 'erases the palette once the completion closes' do
      io = tty(80)
      frame = started(io)
      frame.complete(completing('/'))

      frame.complete(completing('/', :escape))

      assert_operator io.string, :end_with?, "\e[3A\r\e[J\r\n› /\r\n  \e[1A\e[4G"
    end

    it 'leaves the cursor at the edit point' do
      frame = on_pty

      frame.complete(completing('/', 'm', 'o'))

      assert_equal [2, 5], [@pty.screen.row, @pty.screen.column]
    end
  end

  describe '#status' do
    it 'draws nothing when there is no footer' do
      io = StringIO.new

      started(io).status('working')

      assert_equal '', io.string
    end

    it 'redraws the footer with the status indented under the input line' do
      io = tty(80)

      started(io).status('working')

      assert_equal "#{empty_frame}\e[1A\r\e[J\r\n› \r\n  working\e[1A\e[3G", io.string
    end

    it 'leaves the cursor on the input line' do
      frame = on_pty

      frame.status('working')

      assert_equal [1, 2], [@pty.screen.row, @pty.screen.column]
    end
  end

  describe '#hint' do
    it 'draws nothing when there is no footer' do
      io = StringIO.new

      started(io).hint('answer')

      assert_equal '', io.string
    end

    it 'redraws the footer with the hint in place of the status' do
      io = tty(80)
      frame = started(io)
      frame.status('working')

      frame.hint('answer')

      assert_operator io.string, :end_with?, "\e[J\r\n› \r\n  answer\e[1A\e[3G"
    end

    it 'keeps the hint over a status set after it' do
      io = tty(80)
      frame = started(io)
      frame.hint('answer')

      frame.status('working')

      assert_operator io.string, :end_with?, "\e[J\r\n› \r\n  answer\e[1A\e[3G"
    end

    it 'brings back the status once the hint is cleared' do
      io = tty(80)
      frame = started(io)
      frame.status('working')
      frame.hint('answer')

      frame.hint(nil)

      assert_operator io.string, :end_with?, "\e[J\r\n› \r\n  working\e[1A\e[3G"
    end

    it 'leaves the cursor on the input line' do
      frame = on_pty

      frame.hint('answer')

      assert_equal [1, 2], [@pty.screen.row, @pty.screen.column]
    end
  end

  describe '#queued' do
    it 'draws nothing when there is no footer' do
      io = StringIO.new

      started(io).queued(2)

      assert_equal '', io.string
    end

    it 'redraws the footer with the count after the input line' do
      io = tty(80)

      started(io).queued(2)

      assert_equal "#{empty_frame}\e[1A\r\e[J\r\n›    · 2 queued\r\n  \e[1A\e[3G", io.string
    end

    it 'leaves the cursor at the edit point' do
      frame = on_pty
      frame.input(editing('hi', 'yo'))

      frame.queued(2)

      assert_equal [1, 4], [@pty.screen.row, @pty.screen.column]
    end
  end

  describe '#jobs' do
    it 'draws nothing when there is no footer' do
      io = StringIO.new

      started(io).jobs(2)

      assert_equal '', io.string
    end

    it 'redraws the footer with the count on the status line' do
      io = tty(80)

      started(io).jobs(2)

      assert_equal "#{empty_frame}\e[1A\r\e[J\r\n› \r\n  2 jobs running\e[1A\e[3G", io.string
    end

    it 'leaves the cursor on the input line' do
      frame = on_pty

      frame.jobs(2)

      assert_equal [1, 2], [@pty.screen.row, @pty.screen.column]
    end
  end

  describe '#status_room' do
    it 'is nothing when there is no footer' do
      assert_equal 0, started(StringIO.new).status_room
    end

    it 'is the row less the indent and the free last column' do
      assert_equal 77, started(tty(80)).status_room
    end

    it 'leaves out the columns of the job counter and its separator' do
      frame = started(tty(80))

      frame.jobs(2)

      assert_equal 60, frame.status_room
    end

    it 'keeps the columns of a job counter the width has no room to draw' do
      frame = started(tty(16))

      frame.jobs(2)

      assert_equal 13, frame.status_room
    end
  end

  describe '#peek' do
    it 'draws nothing when there is no footer' do
      io = StringIO.new

      started(io).peek('thinking')

      assert_equal '', io.string
    end

    it 'redraws the footer under the content' do
      io = tty(80)

      started(io).peek('thinking')

      assert_equal "#{empty_frame}\e[1A\r\e[J\r\n  thinking\r\n#{empty_footer}", io.string
    end

    it 'erases every row it drew before drawing the next content' do
      io = tty(80)
      frame = started(io)
      frame.peek("thinking\nhard")

      frame.peek('done')

      assert_operator io.string, :end_with?, "\e[3A\r\e[J\r\n  done\r\n#{empty_footer}"
    end

    it 'leaves the blank row, the input line and the status line as they were' do
      frame = on_pty
      frame.input(editing('hi'))
      frame.status('working')

      frame.peek('thinking')

      assert_equal ['', '  thinking', '› hi', '  working'], @pty.screen.rows
    end

    it 'leaves the cursor at the edit point' do
      frame = on_pty
      frame.input(editing('hi', 'yo'))

      frame.peek("thinking\nhard")

      assert_equal [3, 4], [@pty.screen.row, @pty.screen.column]
    end
  end

  describe '#stop' do
    it 'writes nothing when there is no footer' do
      io = StringIO.new

      started(io).stop

      assert_equal '', io.string
    end

    it 'erases the frame from its blank row' do
      io = tty(80)

      started(io).stop

      assert_equal "#{empty_frame}\e[1A\r\e[J", io.string
    end

    it 'erases the peek with the frame' do
      io = tty(80)
      frame = started(io)
      frame.peek('thinking')

      frame.stop

      assert_operator io.string, :end_with?, "#{empty_footer}\e[2A\r\e[J"
    end

    it 'erases the loading line when it stops before any content' do
      io = tty(80)

      started(io, loading: true).stop

      assert_equal "  loading…\r\e[J", io.string
    end

    it 'leaves the cursor at the start of the row under the content' do
      frame = on_pty
      frame.append('one')

      frame.stop

      assert_equal [1, 0], [@pty.screen.row, @pty.screen.column]
    end

    it 'prints later content without a frame' do
      io = tty(80)
      frame = started(io)

      frame.stop
      frame.append('one')

      assert_equal "#{empty_frame}\e[1A\r\e[Jone\n", io.string
    end

    it 'restores the resize handler it replaced' do
      handler = proc {}
      original = Signal.trap('WINCH', handler)

      started(tty(80)).stop

      assert_same handler, Signal.trap('WINCH', original)
    end
  end

  describe '#measure' do
    it 'is the size of its own io' do
      assert_equal [24, 80], frame(tty(80)).measure
    end
  end

  describe '#resize' do
    it 'refits the footer when the terminal is resized' do
      frame = on_pty(columns: 40)
      frame.status('working through the queue')

      @pty.resize(12)

      assert_equal ['', '›', '  working t'], @pty.screen.rows
    end

    it 'leaves the cursor at the edit point after a resize' do
      frame = on_pty(columns: 40)
      frame.input(editing('abcdefghij'))

      @pty.resize(8)

      assert_equal [1, 7], [@pty.screen.row, @pty.screen.column]
    end

    it 'keeps the last width when the new one is unknowable' do
      frame = on_pty(columns: 12)
      frame.status('working through the queue')

      @pty.report(0)

      assert_equal ['', '›', '  working t'], @pty.screen.rows
    end

    it 'refits the peek to the rows left above the footer' do
      frame = on_pty(columns: 40, rows: 12)
      frame.peek("one\ntwo\nthree\nfour")

      @pty.report(40, rows: 5)

      assert_equal ['', '  three', '  four', '›', ''], @pty.screen.rows
    end
  end

  describe '#peek_rows' do
    def peeking(columns, content, rows: 24, color: false)
      io = tty(columns, rows: rows)
      started(io, color: color).peek(content)
      io.string.delete_prefix("#{empty_frame}\e[1A\r\e[J\r\n")
    end

    it 'draws no more rows than a short terminal has above its frame' do
      assert_equal "  two\r\n  three\r\n#{empty_footer}", peeking(80, "one\ntwo\nthree", rows: 5)
    end

    it 'draws no row on a terminal with none above its frame' do
      assert_equal empty_footer, peeking(80, 'thinking', rows: 3)
    end

    it 'draws the last lines of content that outgrows the region' do
      lines = Array.new(10) { |n| "line #{n}" }

      assert_equal "#{lines.last(8).map { |line| "  #{line}\r\n" }.join}#{empty_footer}", peeking(80, lines.join("\n"))
    end

    it 'wraps the content at the free last column' do
      assert_equal "  abcde\r\n  fg hi\r\n#{empty_footer}", peeking(8, 'abcde fg hi')
    end

    it 'keeps a blank line of the content' do
      assert_equal "  one\r\n\r\n  two\r\n#{empty_footer}", peeking(80, "one\n\ntwo")
    end

    it 'draws the last rows of a line that wraps past the region' do
      words = Array.new(10) { |n| "word#{n}" }

      assert_equal "#{words.last(8).map { |word| "  #{word}\r\n" }.join}#{empty_footer}", peeking(8, words.join(' '))
    end

    it 'cuts each row to a width that has no room for the indent' do
      assert_equal "  \r\n  \r\n#{empty_footer}", peeking(3, 'ab')
    end

    it 'never leaves a row behind in the scrollback of a full screen' do
      frame = on_pty(rows: 5)
      5.times { |n| frame.append("line #{n}") }

      frame.peek(Array.new(10) { |n| "peeked #{n}" }.join("\n"))
      frame.peek('')

      assert_equal [*Array.new(5) { |n| "line #{n}" }, '', '›', ''], @pty.screen.scrollback + @pty.screen.rows
    end

    it 'dims each row when color is on' do
      assert_includes peeking(80, "one\ntwo", color: true), "\e[2m  one\e[0m\r\n\e[2m  two\e[0m\r\n"
    end
  end

  describe '#palette_rows' do
    def completed(columns, completion, rows: 24, color: false)
      io = tty(columns, rows: rows)
      started(io, color: color).complete(completion)
      io.string.delete_prefix("#{empty_frame}\e[1A\r\e[J\r\n")
    end

    it 'draws no more rows than a short terminal has above its frame' do
      shown = completed(80, completing('/', listed: commands('auth' => 'a', 'commit' => 'c', 'model' => 'm')), rows: 5)

      assert_equal "▸ /auth    a\r\n  /commit  c\r\n› /auth\r\n  \e[1A\e[4G", shown
    end

    it 'leaves the peek the rows the palette does not take' do
      io = tty(80, rows: 6)
      frame = started(io)
      frame.peek("one\ntwo")

      frame.complete(completing('/'))

      assert_operator io.string, :end_with?, "\e[3A\r\e[J\r\n  two\r\n#{palette}› /auth\r\n  \e[1A\e[4G"
    end

    it 'scrolls the matches to keep the selection on the last row' do
      rows = (2..8).map { |n| "  /c#{n}  about #{n}\r\n" }.join
      shown = completed(80, completing('/', :up, listed: commands((0..9).to_h { |n| ["c#{n}", "about #{n}"] })))

      assert_equal "#{rows}▸ /c9  about 9\r\n› /c9\r\n  \e[1A\e[4G", shown
    end

    it 'joins the lines of a description into one row' do
      listed = commands('auth' => "Store\ncredentials\n")

      assert_operator completed(80, completing('/', listed:)), :start_with?, "▸ /auth  Store credentials\r\n"
    end

    it 'paints the selected name and dims each description when color is on' do
      row = "▸ \e[38;2;255;106;193m/auth \e[0m  \e[2mStore credentials\e[0m\r\n"

      assert_includes completed(80, completing('/'), color: true), row
    end

    it 'cuts each row at the free last column' do
      assert_operator completed(12, completing('/')), :start_with?, "▸ /auth   S\r\n  /model  S\r\n"
    end
  end

  describe '#footer' do
    it 'keeps the last column free' do
      io = tty(10)

      started(io).status('0123456789')

      assert_operator io.string, :end_with?, "\r\n  0123456\e[1A\e[3G"
    end

    it 'shows the text nearest the cursor when the input outgrows the width' do
      io = tty(8)

      started(io, editor: editing('abcdefgh'))

      assert_equal "\r\n› defgh\r\n  \e[1A\e[8G", io.string
    end

    it 'fills the room left after the cursor with the text that follows it' do
      io = tty(8)

      started(io, editor: editing('ab', 'cdefgh'))

      assert_equal "\r\n› abcde\r\n  \e[1A\e[5G", io.string
    end

    it 'places the cursor by columns, not characters' do
      io = tty(80)

      started(io, editor: editing('日本'))

      assert_equal "\r\n› 日本\r\n  \e[1A\e[7G", io.string
    end

    it 'cuts the prompt when the width has no room for it' do
      io = tty(2)

      started(io, editor: editing('hi'))

      assert_equal "\r\n›\r\n \e[1A\e[2G", io.string
    end

    it 'keeps the style reset of a status cut short' do
      io = tty(8)

      started(io).status("\e[2mworking\e[0m")

      assert_operator io.string, :end_with?, "\r\n  \e[2mworki\e[0m\e[1A\e[3G"
    end

    it 'draws the rest of the selected name after the cursor' do
      io = tty(80)

      started(io).complete(completing('/', 'm', 'o'))

      assert_operator io.string, :end_with?, "› /model\r\n  \e[1A\e[6G"
    end

    it 'cuts the rest of the name at the free last column' do
      io = tty(7)

      started(io).complete(completing('/', 'm', 'o'))

      assert_operator io.string, :end_with?, "› /mod\r\n  \e[1A\e[6G"
    end

    it 'dims the rest of the name when color is on' do
      io = tty(80)

      started(io, color: true).complete(completing('/', 'm', 'o'))

      assert_includes io.string, "/mo\e[2mdel\e[0m\r\n"
    end
  end

  describe '#chip' do
    it 'is left out once nothing is queued' do
      io = tty(80)
      frame = started(io)

      frame.queued(2)
      frame.queued(0)

      assert_operator io.string, :end_with?, "\e[J#{empty_frame}"
    end

    it 'is left out rather than cut short when the width has no room for it' do
      io = tty(17)

      started(io, editor: editing('hi')).queued(2)

      assert_operator io.string, :end_with?, "\e[J\r\n› hi\r\n  \e[1A\e[5G"
    end

    it 'is dimmed when color is on' do
      io = tty(80)

      started(io, color: true).queued(2)

      assert_operator io.string, :end_with?, "\e[0m    \e[2m· 2 queued\e[0m\r\n  \e[1A\e[3G"
    end

    it 'follows the text either side of the cursor' do
      io = tty(80)

      started(io, editor: editing('hi', 'yo')).queued(2)

      assert_operator io.string, :end_with?, "› hiyo   · 2 queued\r\n  \e[1A\e[5G"
    end

    it 'follows the rest of a completed name' do
      io = tty(80)
      frame = started(io)
      frame.complete(completing('/', 'm', 'o'))

      frame.queued(2)

      assert_operator io.string, :end_with?, "› /model   · 2 queued\r\n  \e[1A\e[6G"
    end

    it 'fills the input line up to the free last column' do
      io = tty(18)

      started(io, editor: editing('hi')).queued(2)

      assert_operator io.string, :end_with?, "› hi   · 2 queued\r\n  \e[1A\e[5G"
    end
  end

  describe '#status_line' do
    def counting(columns, jobs, status: '', color: false)
      io = tty(columns)
      frame = started(io, color: color)
      frame.status(status)
      frame.jobs(jobs)
      io.string
    end

    it 'is the status alone once no job is running' do
      io = tty(80)
      frame = started(io)
      frame.status('working')

      frame.jobs(2)
      frame.jobs(0)

      assert_operator io.string, :end_with?, "\e[J\r\n› \r\n  working\e[1A\e[3G"
    end

    it 'is the status alone rather than a counter cut short when the width has no room for it' do
      assert_operator counting(16, 2, status: 'working'), :end_with?, "\r\n  working\e[1A\e[3G"
    end

    it 'counts one job in the singular' do
      assert_operator counting(80, 1), :end_with?, "\r\n  1 job running\e[1A\e[3G"
    end

    it 'counts several jobs in the plural' do
      assert_operator counting(80, 12), :end_with?, "\r\n  12 jobs running\e[1A\e[3G"
    end

    it 'puts the counter after the status' do
      assert_operator counting(80, 2, status: 'working'), :end_with?, "\r\n  working · 2 jobs running\e[1A\e[3G"
    end

    it 'puts the counter after a hint' do
      io = tty(80)
      frame = started(io)
      frame.hint('answer')

      frame.jobs(2)

      assert_operator io.string, :end_with?, "\r\n  answer · 2 jobs running\e[1A\e[3G"
    end

    it 'cuts the status short to keep the counter whole on the one row' do
      assert_operator counting(26, 2, status: 'working through'), :end_with?, "\r\n  workin · 2 jobs running\e[1A\e[3G"
    end

    it 'draws the counter alone when the width has no room for any status' do
      assert_operator counting(20, 2, status: 'working'), :end_with?, "\r\n  2 jobs running\e[1A\e[3G"
    end

    it 'leaves no separator after a status cut down to its styles' do
      output = counting(20, 2, status: "\e[2mworking\e[0m")

      assert_operator output, :end_with?, "\r\n  \e[2m\e[0m2 jobs running\e[1A\e[3G"
    end

    it 'fills the status line up to the free last column' do
      assert_operator counting(17, 2), :end_with?, "\r\n  2 jobs running\e[1A\e[3G"
    end

    it 'dims the counter when color is on' do
      assert_operator counting(80, 2, color: true), :end_with?, "\r\n  \e[2m2 jobs running\e[0m\e[1A\e[3G"
    end

    it 'dims the separator with the counter when color is on' do
      output = counting(80, 2, status: 'working', color: true)

      assert_operator output, :end_with?, "\r\n  working\e[2m · 2 jobs running\e[0m\e[1A\e[3G"
    end
  end
end
