# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/display_runtime'
require_relative '../../../support/frame_pty'

describe Riffer::Rig::Terminal::TickerDisplay do
  before do
    @theme = Riffer::Rig::Terminal::Theme.new(enabled: false)
    @pty = FramePty.new(columns: 60, rows: 12)
    @frame = Riffer::Rig::Terminal::Frame.new(io: @pty.slave, theme: @theme)
    @frame.start
    @peek = Riffer::Rig::Terminal::Peek.new(frame: @frame)
    @catalog = Riffer::Catalog.new(models: {}, aliases: {})
    @runtime = DisplayRuntime.new
  end

  after do
    @display&.finish(@runtime)
    @frame.stop
    @pty.close
  end

  def display(theme: @theme)
    @display ||= Riffer::Rig::Terminal::TickerDisplay.new(
      frame: @frame,
      theme: theme,
      peek: @peek,
      catalog: @catalog,
      random: Random.new(1),
      clock: -> { 0.0 }
    )
  end

  def show(*events, runtime: @runtime)
    display.start(runtime)
    events.each { |event| display.absorb(event) }
    display.finish(runtime)
  end

  def rows
    @pty.screen.rows
  end

  def status
    rows.last
  end

  def await
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + FramePty::TIMEOUT_SECONDS
    sleep 0.01 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  def toggle_peek
    @peek.press(Riffer::Rig::Terminal::Key.new(:ctrl_t))
  end

  def text(content)
    Riffer::StreamEvents::TextDelta.new(content)
  end

  def turn_end
    Riffer::Rig::Events::TurnEnd.new(:completed, nil)
  end

  describe '#start' do
    it "prices the ticker's estimate at the rates of the Runtime's model" do
      @catalog = Riffer::Catalog.new(
        models: { 'mock/test' => { pricing: Riffer::Catalog::Rates.new(input: 0.0, output: 1_000_000.0) } },
        aliases: {}
      )
      display.start(@runtime)

      display.absorb(text('x' * 8))
      await { status.include?('↓2 tok') }

      assert_includes status, '$2.000'
    end

    it 'has the peek watch the turn' do
      display.start(@runtime)
      display.absorb(text('Let me look.'))

      toggle_peek

      assert_equal '  Let me look.', rows[1]
    end

    it 'draws the ticker on the status line' do
      display.start(@runtime)

      assert_equal ['', '›', '  ▁▅██▆▂▄ 00:00 · ↓0 tok · riffing…'], rows
    end
  end

  describe '#absorb' do
    it 'counts what the turn sends on the ticker' do
      display.start(@runtime)

      display.absorb(text('Let me look.'))
      await { status.include?('step') }

      assert_includes status, 'step 1'
    end

    it 'keeps an open peek up with the turn' do
      display.start(@runtime)
      toggle_peek

      display.absorb(text('Let me look.'))

      assert_equal '  Let me look.', rows[1]
    end
  end

  describe '#cancel' do
    it 'leaves the status line alone once the turn is over' do
      show(turn_end)

      display.cancel(@runtime)

      assert_empty status
    end

    it 'leaves the Runtime alone once the turn is over' do
      show(turn_end)

      display.cancel(@runtime)

      assert_equal 0, @runtime.cancels
    end

    it 'stops the ticker redrawing the status line' do
      idle = Thread.list
      display.start(@runtime)

      display.cancel(@runtime)

      assert_empty Thread.list - idle
    end

    it 'shows stopping in place of the ticker' do
      display.start(@runtime)

      display.cancel(@runtime)

      assert_equal ['', '›', '  stopping…'], rows
    end

    it 'dims the stopping status when color is on' do
      display(theme: Riffer::Rig::Terminal::Theme.new(enabled: true)).start(@runtime)

      display.cancel(@runtime)

      assert_includes @pty.transcript, "\e[2mstopping…\e[0m"
    end

    it 'cancels the Runtime with the stopping status already showing' do
      seen = nil
      runtime = DisplayRuntime.new(on_cancel: -> { seen = rows })
      display.start(runtime)

      display.cancel(runtime)

      assert_equal ['', '›', '  stopping…'], seen
    end

    it 'cancels the Runtime' do
      display.start(@runtime)

      display.cancel(@runtime)

      assert_equal 1, @runtime.cancels
    end
  end

  describe '#finish' do
    it 'clears the ticker from the status line' do
      show

      assert_equal ['', '›', ''], rows
    end

    it 'clears the stopping status of a cancelled turn' do
      display.start(@runtime)
      display.cancel(@runtime)

      display.finish(@runtime)

      assert_equal ['', '›', ''], rows
    end

    it 'hides the peek' do
      display.start(@runtime)
      display.absorb(text('Let me look.'))
      toggle_peek

      display.finish(@runtime)

      assert_equal ['', '›', ''], rows
    end

    it 'prints nothing for a turn that has not ended' do
      show(text('Half a sen'))

      assert_equal ['', '›', ''], rows
    end

    it 'prints the answer and the stat footer above the footer' do
      show(text('All done.'), turn_end)

      assert_equal ['', '  All done.', '', '  1 step · 00:00', '', '›', ''], rows
    end

    it 'reports the session total of the Runtime' do
      tally = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)

      show(turn_end, runtime: DisplayRuntime.new(tally: tally))

      assert_equal ['', '  0 steps · 00:00 · session 15 tok', '', '›', ''], rows
    end

    it 'wraps the report to the width of the terminal' do
      @pty.resize(12)

      show(text('one two three four five'), turn_end)

      assert_equal ['  one two', '  three four', '  five'], rows[1, 3]
    end
  end
end
