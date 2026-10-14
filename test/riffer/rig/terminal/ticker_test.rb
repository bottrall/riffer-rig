# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/frame_pty'

class TickerFooter
  attr_reader :statuses
  attr_accessor :status_room

  def initialize
    @status_room = 120
    @statuses = []
  end

  def status(status)
    @statuses << status
  end
end

describe Riffer::Rig::Terminal::Ticker do
  before { @now = 0.0 }

  after do
    @ticker&.stop
    @frame&.stop
    @pty&.close
  end

  def footer
    @footer ||= TickerFooter.new
  end

  def buffer
    @buffer ||= Riffer::Rig::Terminal::TurnBuffer.new(clock: -> { @now })
  end

  def ticker(color: false, rates: nil)
    @ticker ||= Riffer::Rig::Terminal::Ticker.new(
      footer: @frame || footer,
      theme: Riffer::Rig::Terminal::Theme.new(enabled: color),
      buffer: buffer,
      rates: rates,
      random: Random.new(1)
    )
  end

  def drawn(*events)
    events.each { |event| ticker.absorb(event) }
    ticker.tick
    footer.statuses.last
  end

  def await
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    Thread.pass until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  def on_pty(columns: 80)
    @pty = FramePty.new(columns: columns, rows: 30)
    @frame = Riffer::Rig::Terminal::Frame.new(io: @pty.slave, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
    @frame.start
  end

  def text(content)
    Riffer::StreamEvents::TextDelta.new(content)
  end

  def reasoning(content)
    Riffer::StreamEvents::ReasoningDelta.new(content)
  end

  def tool_arguments(arguments)
    Riffer::StreamEvents::ToolCallDelta.new(item_id: 'call_1', arguments_delta: arguments)
  end

  def tool_call
    Riffer::StreamEvents::ToolCallDone.new(item_id: 'call_1', call_id: 'call_1', name: 'read', arguments: '{}')
  end

  def tools_run
    [
      Riffer::Rig::Events::BeforeToolCall.new('call_1', 'read', {}, 0.0),
      Riffer::Rig::Events::AfterToolCall.new('call_1', 'read', {}, Riffer::Tools::Response.text('ok'), 0.0, 0.0)
    ]
  end

  def usage(input, output, cost: nil)
    Riffer::StreamEvents::TokenUsageDone.new(
      token_usage: Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output, cost: cost)
    )
  end

  def turn_end
    Riffer::Rig::Events::TurnEnd.new(:completed, nil)
  end

  def output_rate(per_million)
    Riffer::Config::Pricing::Rates.new(input: 0.0, output: per_million)
  end

  describe '#start' do
    it 'draws the first frame before the turn sends anything' do
      ticker.start

      assert_equal '▁▅██▆▂▄ 00:00 · ↓0 tok · riffing…', footer.statuses.first
    end

    it 'keeps the clock ticking while the turn sends nothing' do
      ticker.start

      @now = 61.0
      await { footer.statuses.last.include?('01:01') }

      assert_includes footer.statuses.last, '01:01'
    end
  end

  describe '#absorb' do
    it 'passes each event on to the buffer' do
      ticker.absorb(text('All done.'))
      ticker.absorb(turn_end)

      assert_equal 'All done.', buffer.answer
    end

    it 'draws no frame from an event half absorbed' do
      ticker
      parking = [true]
      buffer.define_singleton_method(:absorb) do |event|
        Thread.stop if parking.shift
        super(event)
      end

      absorbing = Thread.new { ticker.absorb(tool_call) }
      Thread.pass until absorbing.stop?
      drawing = Thread.new { ticker.tick }
      Thread.pass until drawing.stop?
      absorbing.run
      [absorbing, drawing].each(&:join)

      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · 1 tool · ↓0 tok · riffing…', footer.statuses.last
    end

    it 'labels the frame with a reasoning phrase while the model reasons' do
      assert_equal '▁▅██▆▂▄ 00:00 · ↓0 tok · herding thoughts…', drawn(reasoning('hmm'))
    end

    it 'returns to the neutral label at the next event' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↓1 tok · riffing…', drawn(reasoning('hmm'), text('Hi'))
    end

    it 'estimates a token for every four characters of reasoning' do
      assert_equal '▁▅██▆▂▄ 00:00 · ↓100 tok · herding thoughts…', drawn(reasoning('x' * 400))
    end

    it 'estimates a token for every four characters of prose' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↓100 tok · riffing…', drawn(text('x' * 400))
    end

    it 'estimates a token for every four characters of tool arguments' do
      assert_equal '▁▅██▆▂▄ 00:00 · ↓100 tok · riffing…', drawn(tool_arguments('x' * 400))
    end

    it 'counts each tool the model calls' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · 3 tools · ↓0 tok · riffing…', drawn(tool_call, tool_call, tool_call)
    end

    it 'drops the estimate for the usage the request reports' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↑1.2k ↓80 tok · riffing…', drawn(text('x' * 400), usage(1_200, 80))
    end

    it 'estimates what streams after a usage report on top of it' do
      status = drawn(text('x' * 400), usage(1_200, 80), text('x' * 40))

      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↑1.2k ↓90 tok · riffing…', status
    end

    [
      Riffer::StreamEvents::SkillActivation.new('review'),
      Riffer::Rig::Events::SkillActivated.new('review')
    ].each do |activation|
      it "labels the frame with the skill of a #{activation.class.name.split('::').last} event" do
        assert_equal '▁▅██▆▂▄ 00:00 · ↓0 tok · ✦ skill: review', drawn(activation)
      end
    end
  end

  describe '#tick' do
    it 'fits each frame to the room the footer has for it' do
      ticker.tick
      footer.status_room = 13
      ticker.tick

      assert_equal ['▁▅██▆▂▄ 00:00 · ↓0 tok · riffing…', '▅██▆▂▄▇ 00:00'], footer.statuses
    end

    it 'draws the equalizer a column further along each frame' do
      3.times { ticker.tick }

      assert_equal(
        [
          '▁▅██▆▂▄ 00:00 · ↓0 tok · riffing…',
          '▅██▆▂▄▇ 00:00 · ↓0 tok · riffing…',
          '██▆▂▄▇█ 00:00 · ↓0 tok · riffing…'
        ],
        footer.statuses
      )
    end
  end

  describe '#stop' do
    it 'ends the thread that draws the frames' do
      running = Thread.list
      ticker.start

      ticker.stop

      assert_empty Thread.list - running
    end

    it 'clears the status line of a ticker that never started' do
      ticker.stop

      assert_equal [''], footer.statuses
    end

    it 'clears the status line' do
      ticker.start

      ticker.stop

      assert_equal '', footer.statuses.last
    end
  end

  describe '#roll' do
    it 'holds a reasoning phrase until its time is up' do
      drawn(reasoning('hmm'))

      19.times { ticker.tick }

      assert_equal '▇▅▁▅██▆ 00:00 · ↓0 tok · herding thoughts…', footer.statuses.last
    end

    it 'rolls the next phrase once the time is up' do
      drawn(reasoning('hmm'))

      20.times { ticker.tick }

      assert_equal '▅▁▅██▆▂ 00:00 · ↓0 tok · warming up…', footer.statuses.last
    end
  end

  describe '#line' do
    it 'paints the equalizer and dims the segments when color is on' do
      ticker(color: true)

      assert_equal(
        "\e[38;2;45;226;230m▁\e[0m\e[38;2;192;76;253m▅\e[0m\e[38;2;45;226;230m█\e[0m\e[38;2;192;76;253m█\e[0m" \
        "\e[38;2;45;226;230m▆\e[0m\e[38;2;192;76;253m▂\e[0m\e[38;2;45;226;230m▄\e[0m " \
        "\e[2m00:00 · step 1 · ↓1 tok · riffing…\e[0m",
        drawn(text('Hello'))
      )
    end

    {
      'keeps every segment the room has columns for' =>
        [70, '▁▅██▆▂▄ 00:00 · step 1 · 1 tool · ↑18.2k ↓3.1k tok · $0.071 · riffing…'],
      'sheds the label first' => [69, '▁▅██▆▂▄ 00:00 · step 1 · 1 tool · ↑18.2k ↓3.1k tok · $0.071'],
      'sheds the cost after the label' => [58, '▁▅██▆▂▄ 00:00 · step 1 · 1 tool · ↑18.2k ↓3.1k tok'],
      'sheds the tokens after the cost' => [49, '▁▅██▆▂▄ 00:00 · step 1 · 1 tool'],
      'sheds the tool counter after the tokens' => [30, '▁▅██▆▂▄ 00:00 · step 1'],
      'sheds the step counter after the tool counter' => [21, '▁▅██▆▂▄ 00:00'],
      'draws the equalizer alone when the room has no columns for the clock' => [12, '▁▅██▆▂▄']
    }.each do |behaviour, (room, status)|
      it behaviour do
        footer.status_room = room

        assert_equal status, drawn(tool_call, usage(18_240, 3_100, cost: 0.0712))
      end
    end
  end

  describe '#clock' do
    it 'counts the minutes and whole seconds of the turn' do
      ticker

      @now = 61.9

      assert_equal '▁▅██▆▂▄ 01:01 · ↓0 tok · riffing…', drawn
    end

    it 'keeps counting minutes past the hour' do
      ticker

      @now = 3_725.0

      assert_equal '▁▅██▆▂▄ 62:05 · ↓0 tok · riffing…', drawn
    end
  end

  describe '#steps' do
    it 'is left out until a request begins' do
      assert_equal '▁▅██▆▂▄ 00:00 · ↓0 tok · riffing…', drawn
    end

    it 'counts the requests begun' do
      status = drawn(tool_call, *tools_run, text('Hi'))

      assert_equal '▁▅██▆▂▄ 00:00 · step 2 · 1 tool · ↓0 tok · riffing…', status
    end
  end

  describe '#tools' do
    it 'is left out until a tool is called' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↓0 tok · riffing…', drawn(text('Hi'))
    end

    it 'counts one tool in the singular' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · 1 tool · ↓0 tok · riffing…', drawn(tool_call)
    end

    it 'counts several tools in the plural' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · 2 tools · ↓0 tok · riffing…', drawn(tool_call, tool_call)
    end
  end

  describe '#tokens' do
    it 'shows the output alone until a request reports its usage' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↓1.0k tok · riffing…', drawn(text('x' * 4_000))
    end

    it 'shows the input ahead of the output once usage is reported' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↑18.2k ↓3.1k tok · riffing…', drawn(usage(18_240, 3_100))
    end
  end

  describe '#cost' do
    it 'is left out of a turn with no rates and no reported cost' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↑300 ↓150 tok · riffing…', drawn(usage(300, 150))
    end

    it 'prices the estimate at the output rate before any usage is reported' do
      ticker(rates: output_rate(15.0))

      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↓1.0k tok · $0.015 · riffing…', drawn(text('x' * 4_000))
    end

    it 'adds the priced estimate to the cost reported so far' do
      ticker(rates: output_rate(15.0))
      status = drawn(usage(18_240, 3_100, cost: 0.0712), text('x' * 4_000))

      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↑18.2k ↓4.1k tok · $0.086 · riffing…', status
    end

    it 'shows the reported cost alone for a turn with no rates' do
      status = drawn(usage(18_240, 3_100, cost: 0.0712))

      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↑18.2k ↓3.1k tok · $0.071 · riffing…', status
    end
  end

  describe '#count' do
    it 'shows a count under a thousand in full' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↑999 ↓0 tok · riffing…', drawn(usage(999, 0))
    end

    it 'rounds thousands down to a decimal place' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↑18.2k ↓999.9k tok · riffing…', drawn(usage(18_290, 999_999))
    end

    it 'rounds millions down to a decimal place' do
      assert_equal '▁▅██▆▂▄ 00:00 · step 1 · ↑2.3M ↓1.0M tok · riffing…', drawn(usage(2_390_000, 1_000_000))
    end
  end

  describe '#label' do
    it 'keeps a skill label for a beat' do
      drawn(Riffer::Rig::Events::SkillActivated.new('review'))

      15.times { ticker.tick }

      assert_equal '▄▂▆█▇▅▁ 00:00 · ↓0 tok · ✦ skill: review', footer.statuses.last
    end

    it 'returns to the phrase after the beat' do
      drawn(Riffer::Rig::Events::SkillActivated.new('review'))

      16.times { ticker.tick }

      assert_equal '▂▆█▇▅▁▅ 00:00 · ↓0 tok · riffing…', footer.statuses.last
    end

    it 'shows a skill label over a reasoning phrase' do
      status = drawn(Riffer::Rig::Events::SkillActivated.new('review'), reasoning('hmm'))

      assert_equal '▁▅██▆▂▄ 00:00 · ↓0 tok · ✦ skill: review', status
    end
  end

  describe 'in the footer' do
    it 'keeps content above the footer while frames rewrite the status line' do
      on_pty
      ticker

      [
        Thread.new { 20.times { |n| @frame.append("line #{n}") } },
        Thread.new do
          20.times do
            ticker.absorb(text('word '))
            ticker.tick
          end
        end
      ].each(&:join)

      assert_equal(
        [*Array.new(20) { |n| "line #{n}" }, '›', '  ▇▅▁▅██▆ 00:00 · step 1 · ↓25 tok · riffing…'],
        @pty.screen.rows
      )
    end

    it 'keeps content above the footer while its thread ticks between prints' do
      on_pty
      ticker.start

      5.times do |n|
        @frame.append("line #{n}")
        @now = n + 1.0
        await { @pty.transcript.include?("00:0#{n + 1}") }
      end
      ticker.stop

      assert_equal [*Array.new(5) { |n| "line #{n}" }, '›', ''], @pty.screen.rows
    end

    it 'sheds segments to fit a narrow terminal' do
      on_pty(columns: 30)

      ticker.absorb(text('x' * 400))
      ticker.tick

      assert_equal ['›', '  ▁▅██▆▂▄ 00:00 · step 1'], @pty.screen.rows
    end

    it 'sheds segments to keep the job counter whole' do
      on_pty(columns: 40)
      @frame.jobs(2)

      ticker.tick

      assert_equal ['›', '  ▁▅██▆▂▄ 00:00 · 2 jobs running'], @pty.screen.rows
    end
  end
end
