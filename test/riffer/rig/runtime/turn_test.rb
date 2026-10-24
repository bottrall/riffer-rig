# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::Turn do
  before do
    @host = Riffer::Rig::Hosts::Mirror.new(Riffer::Rig::Hosts::Null.new)
    @abort = Riffer::Rig::Runtime::Abort.new
    @agent = Riffer::Agent.new(config: Riffer::Agent::Config.new(model: 'mock/test'))
    @observed = []
    @delivered = []
    @continuations = []
  end

  def hooks
    observe = ->(event) { @observed << event }
    Riffer::Rig::Runtime::Hooks.new(Riffer::Rig::Registrar::EVENTS.to_h { |event| [event, [observe]] }, @host)
  end

  def response(text = 'Done.', steps: 1, usage: nil)
    Riffer::Agent::Response.new(
      text, outcome: Riffer::Agent::Outcome.new(reason: :completed), steps: steps, token_usage: usage
    )
  end

  def stream(*deltas, ending: response)
    Enumerator.new do |yielder|
      deltas.each { |delta| yielder << Riffer::StreamEvents::TextDelta.new(delta) }
      ending
    end
  end

  def stalled(*deltas)
    abort = @abort
    Enumerator.new do |yielder|
      deltas.each { |delta| yielder << Riffer::StreamEvents::TextDelta.new(delta) }
      abort.fire
      sleep 5
      response
    end
  end

  def turn_events(session_start: nil, &start)
    result = nil
    hooks = self.hooks
    turn = Enumerator.new do |yielder|
      @turn = Riffer::Rig::Runtime::Turn.new(
        yielder,
        host: @host,
        abort: @abort,
        agent: -> { @agent },
        hooks: -> { hooks },
        continuation: -> { @continuations.shift },
        deliver: ->(message) { @delivered << message }
      )
      result = @turn.run(session_start, &start)
    end
    [turn.to_a, result]
  end

  def session_start
    Riffer::Rig::Events::SessionStart.new('session-1', :new)
  end

  describe '#run' do
    it 'opens with the session_start it is given' do
      events, = turn_events(session_start: session_start) { stream('hi') }

      assert_instance_of Riffer::Rig::Events::SessionStart, events.first
    end

    it 'observes the session_start' do
      turn_events(session_start: session_start) { stream('hi') }

      assert_instance_of Riffer::Rig::Events::SessionStart, @observed.first
    end

    it 'opens with the stream without a session_start' do
      events, = turn_events { stream('hi') }

      assert_instance_of Riffer::StreamEvents::TextDelta, events.first
    end

    it 'yields what the host queued before the stream' do
      @host.notify('queued', level: :info)
      events, = turn_events { stream('hi') }

      assert_equal Riffer::Rig::Events::Notify.new('queued', :info), events.first
    end

    it 'shows the stream hooks each stream event unchanged' do
      events, = turn_events { stream('a', 'b') }

      assert_equal events.grep(Riffer::StreamEvents::Base).map(&:object_id),
                   @observed.grep(Riffer::StreamEvents::Base).map(&:object_id)
    end

    describe 'continuations' do
      it 'continues no more than the cap' do
        cap = Riffer::Rig::Runtime::Turn::MAX_JOB_CONTINUATIONS
        @continuations.concat(Array.new(cap + 1) { stream })
        turn_events { stream }

        assert_equal 1, @continuations.length
      end

      it 'does not continue a run that did not complete' do
        cut = Riffer::Agent::Response.new('Cut sh', outcome: Riffer::Agent::Outcome.new(reason: :length))
        @continuations << stream(ending: response('Continued.'))
        _, result = turn_events { stream(ending: cut) }

        assert_equal 'Cut sh', result.content
      end

      it 'does not continue a run that used the step limit' do
        @agent = Riffer::Agent.new(config: Riffer::Agent::Config.new(model: 'mock/test', max_steps: 2))
        @continuations << stream(ending: response('Continued.'))
        _, result = turn_events { stream(ending: response('First.', steps: 2)) }

        assert_equal 'First.', result.content
      end

      it 'continues a run with steps left under the limit' do
        @agent = Riffer::Agent.new(config: Riffer::Agent::Config.new(model: 'mock/test', max_steps: 2))
        @continuations << stream(ending: response('Continued.'))
        _, result = turn_events { stream(ending: response('First.', steps: 1)) }

        assert_equal 'Continued.', result.content
      end

      it 'continues the turn with the stream a continuation hands it' do
        @continuations << stream('more', ending: response('Continued.'))
        _, result = turn_events { stream('hi') }

        assert_equal 'Continued.', result.content
      end

      it 'adds the steps of each run' do
        @continuations << stream(ending: response(steps: 2))
        _, result = turn_events { stream(ending: response(steps: 3)) }

        assert_equal 5, result.steps
      end

      it 'adds the token usage of each run' do
        usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
        @continuations << stream(ending: response(usage: usage))
        _, result = turn_events { stream(ending: response(usage: usage)) }

        assert_equal 30, result.token_usage&.total_tokens
      end

      it 'ends the turn once' do
        @continuations << stream('more')
        events, = turn_events { stream('hi') }

        assert_equal [events.last], events.grep(Riffer::Rig::Events::TurnEnd)
      end
    end

    describe 'when aborted' do
      it 'heals the tool calls left without a result' do
        call = Riffer::Messages::Assistant::ToolCall.new(call_id: 'orphan', name: 'read', arguments: '{}')
        @agent.session.add(Riffer::Messages::Assistant.new('', tool_calls: [call]))
        turn_events { stalled }

        assert_equal :interrupted, @agent.session.messages.grep(Riffer::Messages::Tool).first&.error_type
      end

      it 'keeps the text streamed so far as an assistant message' do
        turn_events { stalled('partial ', 'reply') }

        assert_equal 'partial reply', @agent.session.messages.last.content
      end

      it 'delivers the kept message' do
        turn_events { stalled('partial') }

        assert_equal ['partial'], @delivered.map(&:content)
      end

      it 'keeps no message for whitespace' do
        turn_events { stalled(' ') }

        assert_empty @delivered
      end

      it 'streams an interrupt' do
        events, = turn_events { stalled('partial') }

        assert_includes events.map(&:class), Riffer::StreamEvents::Interrupt
      end

      it 'answers with the text streamed so far' do
        _, result = turn_events { stalled('partial') }

        assert_equal 'partial', result.content
      end

      it 'answers as interrupted with the cancelled detail' do
        _, result = turn_events { stalled('partial') }

        assert_equal [:interrupted, 'cancelled'], [result.outcome.reason, result.outcome.detail]
      end

      it 'ends the turn as cancelled' do
        events, = turn_events { stalled('partial') }

        assert_equal :cancelled, events.last.stop_reason
      end
    end

    it 'closes with a turn_end carrying the stop reason' do
      events, = turn_events { stream('hi') }

      assert_equal :completed, events.last.stop_reason
    end

    it 'returns the response' do
      _, result = turn_events { stream('hi', ending: response('All done.')) }

      assert_equal 'All done.', result.content
    end
  end

  describe '#forward' do
    it 'yields the event then what the host queued' do
      notify = Riffer::Rig::Events::Notify.new('mid-turn', :warning)
      events, = turn_events do
        @host.notify('mid-turn', level: :warning)
        @turn.forward(session_start)
        stream
      end

      assert_equal [Riffer::Rig::Events::SessionStart, notify], [events[0].class, events[1]]
    end
  end

  describe '#clear_draft' do
    it 'drops the text streamed before it from an aborted turn' do
      turn = nil
      turn_events do
        turn = @turn
        Enumerator.new do |yielder|
          yielder << Riffer::StreamEvents::TextDelta.new('dropped ')
          turn.clear_draft
          yielder << Riffer::StreamEvents::TextDelta.new('kept')
          @abort.fire
          sleep 5
          response
        end
      end

      assert_equal ['kept'], @delivered.map(&:content)
    end
  end
end
