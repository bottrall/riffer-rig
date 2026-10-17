# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/frame_pty'

class EndedTurn
  attr_reader :answer, :stats

  def initialize(answer:, stats:, interrupted:)
    @answer = answer
    @stats = stats
    @interrupted = interrupted
  end

  def interrupted? = @interrupted
end

describe Riffer::Rig::Terminal::TurnReport do
  def turn(answer: 'All done.', interrupted: false, steps: 2, wall_time: 41.0, usage: nil)
    stats = Riffer::Rig::Terminal::TurnBuffer::Stats.new(steps: steps, wall_time: wall_time, usage: usage)
    EndedTurn.new(answer: answer, stats: stats, interrupted: interrupted)
  end

  def usage(input, output, **rest)
    Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output, **rest)
  end

  def report(turn, session: nil, color: false, width: nil)
    theme = Riffer::Rig::Terminal::Theme.new(enabled: color)
    Riffer::Rig::Terminal::TurnReport.call(turn, session, theme: theme, width: width)
  end

  describe '.call' do
    it 'opens the answer and the footer each below a blank line' do
      assert_equal "\n  All done.\n\n  2 steps · 00:41\n", report(turn)
    end

    it 'prints the footer alone for a turn that gave no answer' do
      assert_equal "\n  2 steps · 00:41\n", report(turn(answer: nil))
    end

    it 'marks an interrupted turn instead of printing its stats' do
      assert_equal "\n  interrupted\n", report(turn(answer: nil, interrupted: true), session: usage(300, 150))
    end

    it 'keeps the partial answer of an interrupted turn above the marker' do
      assert_equal "\n  Half a sen\n\n  interrupted\n", report(turn(answer: 'Half a sen', interrupted: true))
    end

    it 'styles the answer as markdown above a dimmed footer' do
      styled = "\n  All \e[1mdone\e[0m.\n\n\e[2m  2 steps · 00:41\e[0m\n"

      assert_equal styled, report(turn(answer: 'All **done**.'), color: true)
    end

    it 'dims the interrupted marker' do
      assert_equal "\n\e[2m  interrupted\e[0m\n", report(turn(answer: nil, interrupted: true), color: true)
    end

    it 'wraps the footer to the width' do
      spent = turn(answer: nil, usage: usage(1200, 340, cost: 0.071))
      footer = "\n  2 steps · 00:41 ·\n  ↑1200 · ↓340 ·\n  ~$0.0710 · session\n  4500 tok\n"

      assert_equal footer, report(spent, session: usage(3000, 1500), width: 24)
    end

    it 'dims a wrapped footer as one span' do
      spent = turn(answer: nil, usage: usage(1200, 340))

      assert_equal "\n\e[2m  2 steps · 00:41 ·\n  ↑1200 · ↓340\e[0m\n", report(spent, color: true, width: 20)
    end
  end

  describe '.wrap' do
    def wrap(text, width) = Riffer::Rig::Terminal::TurnReport.wrap(text, width)

    it 'leaves a blank line empty' do
      assert_equal "  one\n\n  two", wrap("one\n   \ntwo", 20)
    end

    it 'indents every line when there is no width' do
      assert_equal "  one\n  two", wrap("one\ntwo", nil)
    end

    it 'keeps the spacing of a line that fits the width left of its indent' do
      assert_equal "  anthropic     ok\n  openai        missing", wrap("anthropic     ok\nopenai        missing", 25)
    end

    it 'wraps a line too long for the width left of its indent' do
      assert_equal "  Reads the\n  rows now", wrap('Reads the rows now', 14)
    end
  end

  describe '.answer' do
    it 'prints the footer alone for an answer that renders to nothing' do
      assert_equal "\n  2 steps · 00:41\n", report(turn(answer: " \n"))
    end

    it 'wraps the answer to the width left of its indent' do
      wrapped = "\n  Reads the rows\n  now\n\n  2 steps · 00:41\n"

      assert_equal wrapped, report(turn(answer: 'Reads the rows now'), width: 18)
    end

    it 'indents every line of the answer and leaves its blank lines empty' do
      assert_equal "\n  One.\n\n  Two.\n\n  2 steps · 00:41\n", report(turn(answer: "One.\n\nTwo."))
    end
  end

  describe '.footer' do
    it 'counts a single step in the singular' do
      assert_equal "\n  1 step · 00:41\n", report(turn(answer: nil, steps: 1))
    end

    it 'shows the wall time in whole minutes and seconds' do
      assert_equal "\n  2 steps · 02:05\n", report(turn(answer: nil, wall_time: 125.9))
    end

    it 'closes with the session total and its cost' do
      spent = usage(1200, 340, cost: 0.071)
      footer = "\n  2 steps · 00:41 · ↑1200 · ↓340 · ~$0.0710 · session 4500 tok · ~$0.2500\n"

      assert_equal footer, report(turn(answer: nil, usage: spent), session: usage(3000, 1500, cost: 0.25))
    end

    it 'shows the session total of a turn that reported no usage' do
      assert_equal "\n  2 steps · 00:41 · session 4500 tok\n", report(turn(answer: nil), session: usage(3000, 1500))
    end
  end

  describe '.tokens' do
    it 'shows the real tokens of a turn that reported usage' do
      assert_equal "\n  2 steps · 00:41 · ↑1200 · ↓340\n", report(turn(answer: nil, usage: usage(1200, 340)))
    end

    it 'adds the cache counts of a turn that wrote to and read from the cache' do
      spent = usage(1200, 340, cache_write_tokens: 400, cache_read_tokens: 200)
      footer = "\n  2 steps · 00:41 · ↑1200 · ↓340 · cache_write:400 · cache_read:200\n"

      assert_equal footer, report(turn(answer: nil, usage: spent))
    end

    it 'omits a cache count of zero' do
      spent = usage(1200, 340, cache_write_tokens: 0, cache_read_tokens: 0)

      assert_equal "\n  2 steps · 00:41 · ↑1200 · ↓340\n", report(turn(answer: nil, usage: spent))
    end
  end

  describe '.cost' do
    it 'shows the cost of a priced turn after its tokens' do
      spent = usage(1200, 340, cost: 0.071)

      assert_equal "\n  2 steps · 00:41 · ↑1200 · ↓340 · ~$0.0710\n", report(turn(answer: nil, usage: spent))
    end
  end

  describe 'with a markdown answer' do
    def answered
      answer = <<~MARKDOWN
        ## Picker

        The picker now reads its rows through the **registrar**, not `Session`.

        - one row per session
        - newest first

        ```ruby
        Picker.new(registrar)
        ```
      MARKDOWN
      turn(answer: answer, usage: usage(250, 50))
    end

    def golden(rows)
      rows.map { |row| "#{row}\n" }.join
    end

    it 'prints the answer and the footer in colour' do
      rows = [
        '',
        "  \e[1m\e[38;2;122;92;255mPicker\e[0m\e[0m",
        '',
        "  The picker now reads its rows through the \e[1mregistrar\e[0m, not",
        "  \e[38;2;45;226;230mSession\e[0m.",
        '',
        "  \e[38;2;192;76;253m•\e[0m one row per session",
        "  \e[38;2;192;76;253m•\e[0m newest first",
        '',
        "  \e[2mruby\e[0m",
        "  \e[2m│\e[0m \e[38;2;45;226;230mPicker.new(registrar)\e[0m",
        '',
        "\e[2m  2 steps · 00:41 · ↑250 · ↓50 · session 300 tok\e[0m"
      ]

      assert_equal golden(rows), report(answered, session: usage(250, 50), color: true, width: 60)
    end

    it 'prints the answer and the footer without colour' do
      rows = [
        '',
        '  ## Picker',
        '',
        '  The picker now reads its rows through the registrar, not',
        '  `Session`.',
        '',
        '  • one row per session',
        '  • newest first',
        '',
        '  ruby',
        '  │ Picker.new(registrar)',
        '',
        '  2 steps · 00:41 · ↑250 · ↓50 · session 300 tok'
      ]

      assert_equal golden(rows), report(answered, session: usage(250, 50), width: 60)
    end
  end

  describe 'over two turns' do
    def text(content)
      Riffer::StreamEvents::TextDelta.new(content)
    end

    def finish(reason)
      Riffer::StreamEvents::FinishReasonDone.new(finish_reason: reason)
    end

    def reported(input, output)
      Riffer::StreamEvents::TokenUsageDone.new(token_usage: usage(input, output))
    end

    def tool_run
      [
        Riffer::StreamEvents::ToolCallDone.new(item_id: 'call_1', call_id: 'call_1', name: 'read', arguments: '{}'),
        finish(:tool_calls),
        Riffer::Rig::Events::BeforeToolCall.new('call_1', 'read', {}, 0.0),
        Riffer::Rig::Events::AfterToolCall.new('call_1', 'read', {}, Riffer::Tools::Response.text('ok'), 0.0, 0.0)
      ]
    end

    def play(line, events, seconds:, session:)
      ticks = [0.0, seconds]
      buffer = Riffer::Rig::Terminal::TurnBuffer.new(clock: -> { ticks.shift })
      @frame.append("\n› #{line}")
      [*events, Riffer::Rig::Events::TurnEnd.new(:completed, nil)].each { |event| buffer.absorb(event) }
      @frame.append(Riffer::Rig::Terminal::TurnReport.call(buffer, session, theme: @theme, width: 60))
    end

    before do
      @pty = FramePty.new(columns: 60, rows: 16)
      @theme = Riffer::Rig::Terminal::Theme.new(enabled: false)
      @frame = Riffer::Rig::Terminal::Frame.new(io: @pty.slave, theme: @theme)
      @frame.start
    end

    after do
      @frame.stop
      @pty.close
    end

    it 'leaves a user line, an answer and a stat footer in scrollback for each' do
      looked = [text('Let me look.'), reported(100, 20), *tool_run]
      answered = [text('The picker uses the registrar now.'), finish(:stop), reported(150, 30)]
      play('refactor the picker', [*looked, *answered], seconds: 41.0, session: usage(250, 50))
      fixed = [text('Fixed it.'), finish(:stop), reported(200, 40)]
      play('also fix the flaky test', fixed, seconds: 7.0, session: usage(450, 90))
      scrollback = [
        '',
        '› refactor the picker',
        '',
        '  The picker uses the registrar now.',
        '',
        '  2 steps · 00:41 · ↑250 · ↓50 · session 300 tok',
        '',
        '› also fix the flaky test',
        '',
        '  Fixed it.',
        '',
        '  1 step · 00:07 · ↑200 · ↓40 · session 540 tok'
      ]

      assert_equal scrollback, @pty.screen.rows.first(scrollback.size)
    end
  end
end
