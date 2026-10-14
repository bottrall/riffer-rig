# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/frame_pty'

class CancellableRuntime
  def initialize(on_cancel: -> {})
    @on_cancel = on_cancel
  end

  def cancel
    @on_cancel.call
    nil
  end
end

describe Riffer::Rig::Terminal::Interrupter do
  before do
    @pty = FramePty.new(columns: 40, rows: 6)
    @frame = Riffer::Rig::Terminal::Frame.new(io: @pty.slave, theme: Riffer::Rig::Terminal::Theme.new(enabled: false))
    @frame.start
  end

  after do
    @frame.stop
    @pty.close
  end

  def interrupter(color: false)
    Riffer::Rig::Terminal::Interrupter.new(frame: @frame, theme: Riffer::Rig::Terminal::Theme.new(enabled: color))
  end

  def rows
    @pty.screen.rows
  end

  def turn(*events)
    Riffer::Rig::Terminal::TurnBuffer.new(clock: -> { 0.0 }).tap do |buffer|
      events.each { |event| buffer.absorb(event) }
    end
  end

  def text(content)
    Riffer::StreamEvents::TextDelta.new(content)
  end

  def interrupt
    Riffer::StreamEvents::Interrupt.new(reason: :cancelled)
  end

  def turn_end(stop_reason)
    Riffer::Rig::Events::TurnEnd.new(stop_reason, nil)
  end

  describe '#cancel' do
    it 'shows the stopping status under the input line' do
      interrupter.cancel(CancellableRuntime.new)

      assert_equal ['›', '  stopping…'], rows
    end

    it 'dims the stopping status when color is on' do
      interrupter(color: true).cancel(CancellableRuntime.new)

      assert_includes @pty.transcript, "\e[2mstopping…\e[0m"
    end

    it 'cancels the runtime with the stopping status already showing' do
      seen = nil
      interrupter.cancel(CancellableRuntime.new(on_cancel: -> { seen = rows }))

      assert_equal ['›', '  stopping…'], seen
    end
  end

  describe '#finish' do
    it 'clears the stopping status' do
      interrupter.cancel(CancellableRuntime.new)

      interrupter.finish(turn(turn_end(:completed)))

      assert_equal ['›', ''], rows
    end

    it 'adds nothing to the scrollback for a turn that ran to its end' do
      interrupter.finish(turn(text('All done.'), turn_end(:completed)))

      assert_equal ['›', ''], rows
    end

    it 'marks an interrupted turn that wrote no prose' do
      interrupter.finish(turn(interrupt, turn_end(:cancelled)))

      assert_equal ['interrupted', '›', ''], rows
    end

    it 'prints the partial answer above the marker' do
      interrupter.finish(turn(text('Half a sen'), interrupt, turn_end(:cancelled)))

      assert_equal ['Half a sen', 'interrupted', '›', ''], rows
    end

    it 'drops the whitespace trailing the partial answer' do
      interrupter.finish(turn(text("Half an answer.\n\n"), interrupt, turn_end(:cancelled)))

      assert_equal ['Half an answer.', 'interrupted', '›', ''], rows
    end

    it 'dims the marker when color is on' do
      interrupter(color: true).finish(turn(interrupt, turn_end(:cancelled)))

      assert_includes @pty.transcript, "\e[2minterrupted\e[0m"
    end
  end

  describe 'through a turn the runtime streams' do
    after { @runtime.close }

    def run_turn(prompt)
      buffer = turn
      @runtime.prompt(prompt) { |event| buffer.absorb(event) }
      interrupter.finish(buffer)
    end

    describe 'cancelled while a tool runs, with messages queued' do
      before do
        started = Queue.new
        release = @release = Queue.new
        gate = Class.new(Riffer::Tool) do
          identifier 'gate'
          description 'Blocks until the test releases it'

          define_method(:call) do |**|
            started << true
            release.pop
            text('released')
          end
        end
        gated = Riffer::Rig::Extension.new('gated') { |rig| rig.tool gate }
        @runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [gated])
        @runtime.agent.provider.stub_response('', tool_calls: [{ name: 'gate', arguments: '{}' }])
        @frame.queued(2)
        @turn = Thread.new { run_turn('go') }
        started.pop
        interrupter.cancel(@runtime)
      end

      after { release_tool }

      def release_tool
        @release.close
        @turn.join
      end

      it 'shows stopping beside the queued chip while the cancel drains' do
        assert_equal ['›    · 2 queued', '  stopping…'], rows
      end

      it 'swaps stopping for the marker once the tool has returned' do
        release_tool

        assert_equal ['interrupted', '›    · 2 queued', ''], rows
      end
    end

    describe 'cancelled mid-answer' do
      it 'keeps the partial answer above the marker' do
        stalled = Queue.new
        @runtime = Riffer::Rig::Runtime.new('mock/test')
        @runtime.agent.provider.define_singleton_method(:execute_stream) do |_params, yielder|
          yielder << Riffer::StreamEvents::TextDelta.new('Half a sen')
          stalled << true
          # Stands in for the provider's HTTP read.
          Queue.new.pop(timeout: 5)
        end
        streaming = Thread.new { run_turn('go') }
        stalled.pop
        interrupter.cancel(@runtime)
        streaming.join

        assert_equal ['Half a sen', 'interrupted', '›', ''], rows
      end
    end
  end
end
