# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/frame_pty'

class TickerFooter
  attr_reader :statuses
  attr_accessor :status_room, :jobs

  def initialize
    @status_room = 120
    @jobs = 0
    @statuses = []
  end

  def status(status)
    @statuses << status
  end

  def job_count
    @jobs
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
      rates: rates
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

  def usage(input, output, cost: nil)
    Riffer::StreamEvents::TokenUsageDone.new(
      token_usage: Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output, cost: cost)
    )
  end

  def turn_end
    Riffer::Rig::Events::TurnEnd.new(:completed, nil)
  end

  def output_rate(per_million)
    Riffer::Catalog::Rates.new(input: 0.0, output: per_million)
  end

  describe '#start' do
    it 'draws the first frame before the turn sends anything' do
      ticker.start

      assert_equal '⠋         00:00 ↑0     ↓0 tok     ~$0.0000 0 jobs', footer.statuses.first
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

      assert_equal '⠋ turn 1  00:00 ↑0     ↓0 tok     ~$0.0000 0 jobs', footer.statuses.last
    end

    it 'estimates a token for every four characters of reasoning' do
      assert_equal '⠋         00:00 ↑0     ↓100 tok   ~$0.0000 0 jobs', drawn(reasoning('x' * 400))
    end

    it 'estimates a token for every four characters of prose' do
      assert_equal '⠋ turn 1  00:00 ↑0     ↓100 tok   ~$0.0000 0 jobs', drawn(text('x' * 400))
    end

    it 'estimates a token for every four characters of tool arguments' do
      assert_equal '⠋         00:00 ↑0     ↓100 tok   ~$0.0000 0 jobs', drawn(tool_arguments('x' * 400))
    end

    it 'drops the estimate for the usage the request reports' do
      assert_equal '⠋ turn 1  00:00 ↑1.2k  ↓80 tok    ~$0.0000 0 jobs', drawn(text('x' * 400), usage(1_200, 80))
    end

    it 'estimates what streams after a usage report on top of it' do
      status = drawn(text('x' * 400), usage(1_200, 80), text('x' * 40))

      assert_equal '⠋ turn 1  00:00 ↑1.2k  ↓90 tok    ~$0.0000 0 jobs', status
    end
  end

  describe '#tick' do
    it 'fits each frame to the room the footer has for it' do
      ticker.tick
      footer.status_room = 13
      ticker.tick

      assert_equal ['⠋         00:00 ↑0     ↓0 tok     ~$0.0000 0 jobs', '⠙ 0 jobs'], footer.statuses
    end

    it 'advances the spinner a frame each tick' do
      3.times { ticker.tick }

      assert_equal(
        [
          '⠋         00:00 ↑0     ↓0 tok     ~$0.0000 0 jobs',
          '⠙         00:00 ↑0     ↓0 tok     ~$0.0000 0 jobs',
          '⠹         00:00 ↑0     ↓0 tok     ~$0.0000 0 jobs'
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

  describe '#line' do
    it 'paints the spinner and the cost green, the jobs count amber, and dims the tokens' do
      ticker(color: true)

      assert_equal(
        "\e[38;2;126;201;160m⠋\e[0m turn 1  00:00 \e[2m↑0    \e[0m \e[2m↓1 tok    \e[0m " \
        "\e[38;2;126;201;160m~$0.0000\e[0m \e[38;2;217;176;108m0 jobs\e[0m",
        drawn(text('Hello'))
      )
    end

    {
      'keeps every slot the room has columns for' =>
        [49, '⠋ turn 1  00:00 ↑18.2k ↓3.1k tok  ~$0.0712 0 jobs'],
      'keeps the glyph and the jobs count whole when nothing else fits' => [5, '⠋ 0 jobs']
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

      assert_equal '⠋         01:01 ↑0     ↓0 tok     ~$0.0000 0 jobs', drawn
    end

    it 'keeps counting minutes past the hour' do
      ticker

      @now = 3_725.0

      assert_equal '⠋         62:05 ↑0     ↓0 tok     ~$0.0000 0 jobs', drawn
    end
  end

  describe '#cost' do
    def rates = output_rate(50.0)

    it 'prices the estimate on the model rates' do
      ticker(rates: rates)

      assert_equal '⠋ turn 1  00:00 ↑0     ↓100 tok   ~$0.0050 0 jobs', drawn(text('x' * 400))
    end

    it 'sums the reported usage and the estimate' do
      ticker(rates: rates)

      assert_equal '⠋ turn 1  00:00 ↑1.2k  ↓180 tok   ~$0.0762 0 jobs',
                   drawn(text('x' * 400), usage(1_200, 80, cost: 0.0712), text('x' * 400))
    end
  end
end
