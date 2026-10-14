# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require_relative '../../../support/frame_pty'

describe Riffer::Rig::Terminal::Frame do
  def empty_footer = "› \r\n  \e[1A\e[3G"

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

  def frame(io, color: false, editor: Riffer::Rig::Terminal::LineEditor.new)
    theme = Riffer::Rig::Terminal::Theme.new(enabled: color)
    @frame = Riffer::Rig::Terminal::Frame.new(io: io, theme: theme, editor: editor)
  end

  def started(io, **)
    frame(io, **).tap(&:start)
  end

  def on_pty(columns: 40, rows: 6)
    @pty = FramePty.new(columns: columns, rows: rows)
    started(@pty.slave)
  end

  def editing(before, after = '')
    Riffer::Rig::Terminal::LineEditor.new(before: before, after: after)
  end

  describe '#start' do
    it 'draws no footer when the io is not a tty' do
      io = StringIO.new

      started(io)

      assert_equal '', io.string
    end

    it 'draws no footer when the tty reports zero columns' do
      io = tty(0)

      started(io)

      assert_equal '', io.string
    end

    it 'draws no footer when the window size cannot be queried' do
      io = tty(80)
      io.define_singleton_method(:winsize) { raise Errno::ENOTTY }

      started(io)

      assert_equal '', io.string
    end

    it 'draws the input line over the status line and rests the cursor after the prompt' do
      io = tty(80)

      started(io)

      assert_equal empty_footer, io.string
    end

    it 'paints the prompt when color is on' do
      io = tty(80)

      started(io, color: true)

      assert_equal "\e[38;2;255;106;193m›\e[0m \r\n  \e[1A\e[3G", io.string
    end

    it 'draws the editor it was built with' do
      io = tty(80)

      started(io, editor: editing('hi'))

      assert_equal "› hi\r\n  \e[1A\e[5G", io.string
    end

    it 'draws the peek it was given before it started' do
      io = tty(80)
      unstarted = frame(io)
      unstarted.peek('thinking')

      unstarted.start

      assert_equal "  thinking\r\n#{empty_footer}", io.string
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

    it 'replaces the footer with the content and redraws it below' do
      io = tty(80)

      started(io).append('one')

      assert_equal "#{empty_footer}\r\e[Jone\r\n#{empty_footer}", io.string
    end

    it 'returns the carriage after every line of the content' do
      io = tty(80)

      started(io).append("one\ntwo\r\n")

      assert_includes io.string, "\e[Jone\r\ntwo\r\n›"
    end

    it 'prints the content above the peek' do
      io = tty(80)
      frame = started(io)
      frame.peek('thinking')

      frame.append('one')

      assert_operator io.string, :end_with?, "\e[1A\r\e[Jone\r\n  thinking\r\n#{empty_footer}"
    end

    it 'keeps content above the footer when prints interleave with redraws' do
      frame = on_pty(rows: 30)

      [
        Thread.new { 20.times { |n| frame.append("line #{n}") } },
        Thread.new { 20.times { |n| frame.status("tick #{n}") } },
        Thread.new { 20.times { |n| frame.input(editing('x' * n)) } }
      ].each(&:join)

      assert_equal [*Array.new(20) { |n| "line #{n}" }, "› #{'x' * 19}", '  tick 19'], @pty.screen.rows
    end

    it 'keeps the footer on the last rows once the content scrolls' do
      frame = on_pty(rows: 4)

      5.times { |n| frame.append("line #{n}") }

      assert_equal ['line 3', 'line 4', '›', ''], @pty.screen.rows
    end

    it 'leaves the cursor on the input line' do
      frame = on_pty

      frame.append("one\ntwo")

      assert_equal [2, 2], [@pty.screen.row, @pty.screen.column]
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

      assert_equal "#{empty_footer}\r\e[J› hiyo\r\n  \e[1A\e[5G", io.string
    end

    it 'leaves the cursor at the edit point' do
      frame = on_pty

      frame.input(editing('hi', 'yo'))

      assert_equal [0, 4], [@pty.screen.row, @pty.screen.column]
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

      assert_equal "#{empty_footer}\r\e[J› \r\n  working\e[1A\e[3G", io.string
    end

    it 'leaves the cursor on the input line' do
      frame = on_pty

      frame.status('working')

      assert_equal [0, 2], [@pty.screen.row, @pty.screen.column]
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

      assert_equal "#{empty_footer}\r\e[J›    · 2 queued\r\n  \e[1A\e[3G", io.string
    end

    it 'leaves the cursor at the edit point' do
      frame = on_pty
      frame.input(editing('hi', 'yo'))

      frame.queued(2)

      assert_equal [0, 4], [@pty.screen.row, @pty.screen.column]
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

      assert_equal "#{empty_footer}\r\e[J› \r\n  2 jobs running\e[1A\e[3G", io.string
    end

    it 'leaves the cursor on the input line' do
      frame = on_pty

      frame.jobs(2)

      assert_equal [0, 2], [@pty.screen.row, @pty.screen.column]
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

      assert_equal "#{empty_footer}\r\e[J  thinking\r\n#{empty_footer}", io.string
    end

    it 'erases every row it drew before drawing the next content' do
      io = tty(80)
      frame = started(io)
      frame.peek("thinking\nhard")

      frame.peek('done')

      assert_operator io.string, :end_with?, "\e[2A\r\e[J  done\r\n#{empty_footer}"
    end

    it 'leaves the input line and the status line as they were' do
      frame = on_pty
      frame.input(editing('hi'))
      frame.status('working')

      frame.peek('thinking')

      assert_equal ['  thinking', '› hi', '  working'], @pty.screen.rows
    end

    it 'leaves the cursor at the edit point' do
      frame = on_pty
      frame.input(editing('hi', 'yo'))

      frame.peek("thinking\nhard")

      assert_equal [2, 4], [@pty.screen.row, @pty.screen.column]
    end
  end

  describe '#stop' do
    it 'writes nothing when there is no footer' do
      io = StringIO.new

      started(io).stop

      assert_equal '', io.string
    end

    it 'erases the footer' do
      io = tty(80)

      started(io).stop

      assert_equal "#{empty_footer}\r\e[J", io.string
    end

    it 'erases the peek with the footer' do
      io = tty(80)
      frame = started(io)
      frame.peek('thinking')

      frame.stop

      assert_operator io.string, :end_with?, "#{empty_footer}\e[1A\r\e[J"
    end

    it 'prints later content without a footer' do
      io = tty(80)
      frame = started(io)

      frame.stop
      frame.append('one')

      assert_equal "#{empty_footer}\r\e[Jone\n", io.string
    end

    it 'restores the resize handler it replaced' do
      handler = proc {}
      original = Signal.trap('WINCH', handler)

      started(tty(80)).stop

      assert_same handler, Signal.trap('WINCH', original)
    end
  end

  describe '#resize' do
    it 'refits the footer when the terminal is resized' do
      frame = on_pty(columns: 40)
      frame.status('working through the queue')

      @pty.resize(12)

      assert_equal ['›', '  working t'], @pty.screen.rows
    end

    it 'leaves the cursor at the edit point after a resize' do
      frame = on_pty(columns: 40)
      frame.input(editing('abcdefghij'))

      @pty.resize(8)

      assert_equal [0, 7], [@pty.screen.row, @pty.screen.column]
    end

    it 'keeps the last width when the new one is unknowable' do
      frame = on_pty(columns: 12)
      frame.status('working through the queue')

      @pty.report(0)

      assert_equal ['›', '  working t'], @pty.screen.rows
    end

    it 'refits the peek to the rows left above the footer' do
      frame = on_pty(columns: 40, rows: 12)
      frame.peek("one\ntwo\nthree\nfour")

      @pty.report(40, rows: 4)

      assert_equal ['  three', '  four', '›', ''], @pty.screen.rows
    end
  end

  describe '#peek_rows' do
    def peeking(columns, content, rows: 24, color: false)
      io = tty(columns, rows: rows)
      started(io, color: color).peek(content)
      io.string.delete_prefix("#{empty_footer}\r\e[J")
    end

    it 'draws no more rows than a short terminal has above its footer' do
      assert_equal "  two\r\n  three\r\n#{empty_footer}", peeking(80, "one\ntwo\nthree", rows: 4)
    end

    it 'draws no row on a terminal with none above its footer' do
      assert_equal empty_footer, peeking(80, 'thinking', rows: 2)
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
      frame = on_pty(rows: 4)
      5.times { |n| frame.append("line #{n}") }

      frame.peek(Array.new(10) { |n| "peeked #{n}" }.join("\n"))
      frame.peek('')

      assert_equal [*Array.new(5) { |n| "line #{n}" }, '›', ''], @pty.screen.scrollback + @pty.screen.rows
    end

    it 'dims each row when color is on' do
      assert_includes peeking(80, "one\ntwo", color: true), "\e[J\e[2m  one\e[0m\r\n\e[2m  two\e[0m\r\n"
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

      assert_equal "› defgh\r\n  \e[1A\e[8G", io.string
    end

    it 'fills the room left after the cursor with the text that follows it' do
      io = tty(8)

      started(io, editor: editing('ab', 'cdefgh'))

      assert_equal "› abcde\r\n  \e[1A\e[5G", io.string
    end

    it 'places the cursor by columns, not characters' do
      io = tty(80)

      started(io, editor: editing('日本'))

      assert_equal "› 日本\r\n  \e[1A\e[7G", io.string
    end

    it 'cuts the prompt when the width has no room for it' do
      io = tty(2)

      started(io, editor: editing('hi'))

      assert_equal "›\r\n \e[1A\e[2G", io.string
    end

    it 'keeps the style reset of a status cut short' do
      io = tty(8)

      started(io).status("\e[2mworking\e[0m")

      assert_operator io.string, :end_with?, "\r\n  \e[2mworki\e[0m\e[1A\e[3G"
    end
  end

  describe '#chip' do
    it 'is left out once nothing is queued' do
      io = tty(80)
      frame = started(io)

      frame.queued(2)
      frame.queued(0)

      assert_operator io.string, :end_with?, "\e[J#{empty_footer}"
    end

    it 'is left out rather than cut short when the width has no room for it' do
      io = tty(17)

      started(io, editor: editing('hi')).queued(2)

      assert_operator io.string, :end_with?, "\e[J› hi\r\n  \e[1A\e[5G"
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

      assert_operator io.string, :end_with?, "\e[J› \r\n  working\e[1A\e[3G"
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
