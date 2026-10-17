# frozen_string_literal: true

require 'test_helper'
require_relative '../../../support/provider_streams'

describe Riffer::Rig::Terminal::TurnBuffer do
  def buffer(*events, clock: -> { 0.0 })
    Riffer::Rig::Terminal::TurnBuffer.new(clock: clock).tap do |built|
      events.flatten.each { |event| built.absorb(event) }
    end
  end

  def text(content)
    Riffer::StreamEvents::TextDelta.new(content)
  end

  def tool_call
    Riffer::StreamEvents::ToolCallDone.new(item_id: 'call_1', call_id: 'call_1', name: 'read', arguments: '{}')
  end

  def finish(reason)
    Riffer::StreamEvents::FinishReasonDone.new(finish_reason: reason)
  end

  def usage(input, output)
    Riffer::StreamEvents::TokenUsageDone.new(
      token_usage: Riffer::Providers::TokenUsage.new(input_tokens: input, output_tokens: output)
    )
  end

  def before_tool
    Riffer::Rig::Events::BeforeToolCall.new('call_1', 'read', {}, 0.0)
  end

  def after_tool
    Riffer::Rig::Events::AfterToolCall.new('call_1', 'read', {}, Riffer::Tools::Response.text('ok'), 0.0, 0.0)
  end

  def tools_run
    [before_tool, after_tool]
  end

  def job_exit
    Riffer::Rig::Events::JobExit.new(
      Riffer::Rig::Runtime::JobCompletion.new(
        job_id: 'a1b2c3d4',
        command: 'true',
        exit_status: 0,
        signal: nil,
        duration: 1.0,
        output_path: '/tmp/a1b2c3d4',
        tail: ''
      )
    )
  end

  def interrupt
    Riffer::StreamEvents::Interrupt.new(reason: :cancelled)
  end

  def turn_end
    Riffer::Rig::Events::TurnEnd.new(:completed, nil)
  end

  describe '#absorb' do
    it 'keeps no answer while a request is still streaming' do
      assert_empty buffer(text('Hello')).answer
    end

    it 'keeps no ghost while a request is still streaming' do
      assert_nil buffer(text('Hello')).ghost
    end

    it 'holds the prose of a request that is still streaming' do
      assert_equal 'Hello', buffer(text('Hel'), text('lo')).prose
    end

    describe 'when a request reports its finish reason' do
      it 'holds the prose of that request no longer' do
        assert_empty buffer(text('All done.'), finish(:stop)).prose
      end

      it 'keeps no answer from a request whose prose is blank' do
        assert_empty buffer(text("\n\n"), finish(:stop)).answer
      end

      it 'keeps the earlier ghost when a later request calls tools without prose' do
        turn = buffer(text('Let me look.'), finish(:tool_calls), tools_run, tool_call, finish(:tool_calls))

        assert_equal 'Let me look.', turn.ghost
      end

      it 'keeps the first line of a request that called tools as the ghost' do
        assert_equal 'Let me look.', buffer(text("Let me look.\n\nThen I will compare."), finish(:tool_calls)).ghost
      end

      it 'trims the whitespace around the ghost' do
        assert_equal 'Let me look.', buffer(text("\n  Let me look.  \r\nThen more."), finish(:tool_calls)).ghost
      end

      it 'keeps the prose of a request that called tools out of the answer' do
        assert_empty buffer(text('Let me look.'), finish(:tool_calls)).answer
      end

      it 'joins the deltas of a request that stopped into the answer' do
        assert_equal "All done.\n\nBye.", buffer(text('All '), text("done.\n\nBye."), finish(:stop)).answer
      end

      it 'keeps the prose of a request that stopped out of the ghost' do
        assert_nil buffer(text('All done.'), finish(:stop)).ghost
      end

      (Riffer::Providers::FinishReason::VALUES - %i[stop tool_calls]).each do |reason|
        it "keeps the prose of a request that ended with #{reason} as the answer" do
          assert_equal 'Cut sho', buffer(text('Cut sho'), finish(reason)).answer
        end
      end
    end

    describe 'when tools run' do
      it 'takes the prose of a request that reported no finish reason as a preamble' do
        assert_equal 'Let me look.', buffer(text('Let me look.'), tool_call, before_tool).ghost
      end

      it 'takes it as a preamble when the tool call never ran' do
        assert_equal 'Let me look.', buffer(text('Let me look.'), tool_call, after_tool).ghost
      end

      it 'keeps that preamble out of the next request' do
        assert_equal 'All done.', buffer(text('Let me look.'), tool_call, tools_run, text('All done.'), turn_end).answer
      end

      it 'keeps the answer of a request that reported it stopped' do
        assert_equal 'Here it is.', buffer(text('Here it is.'), tool_call, finish(:stop), before_tool).answer
      end

      it 'names no tool before one starts' do
        assert_nil buffer(text('Let me look.'), tool_call, finish(:tool_calls)).tool
      end

      it 'names the tool that is running' do
        assert_equal 'read', buffer(tool_call, before_tool).tool
      end

      it 'names no tool once it has finished' do
        assert_nil buffer(tool_call, tools_run).tool
      end
    end

    describe 'when the turn is interrupted' do
      it 'keeps the partial prose of the request in flight as the answer' do
        assert_equal 'Half a sen', buffer(text('Half a sen'), interrupt).answer
      end

      it 'keeps a request that already reported tool calls a preamble' do
        assert_empty buffer(text('Let me look.'), finish(:tool_calls), interrupt).answer
      end

      it 'keeps the ghost of the preamble whose tools were running' do
        assert_equal 'Let me look.', buffer(text('Let me look.'), finish(:tool_calls), before_tool, interrupt).ghost
      end
    end

    describe 'when the turn ends' do
      it 'takes the prose of a request that reported no finish reason as the answer' do
        assert_equal 'All done.', buffer(text('All done.'), turn_end).answer
      end

      it 'keeps the answer a finish reason already classified' do
        assert_equal 'All done.', buffer(text('All done.'), finish(:stop), turn_end).answer
      end

      it 'keeps the partial answer of an interrupted turn' do
        assert_equal 'Half a sen', buffer(text('Half a sen'), interrupt, turn_end).answer
      end
    end

    describe 'over a turn of several requests' do
      def turn
        first = [text('Let me look.'), tool_call, finish(:tool_calls), tools_run]
        second = [text('Now the tests.'), tool_call, finish(:tool_calls), tools_run]
        buffer(first, second, text('All done.'), finish(:stop), turn_end)
      end

      it "keeps the last request's answer" do
        assert_equal 'All done.', turn.answer
      end

      it 'keeps the latest preamble as the ghost' do
        assert_equal 'Now the tests.', turn.ghost
      end
    end

    describe 'over a turn a job exit continued' do
      it 'keeps the answer of each reply in order, a blank line apart' do
        turn = buffer(text('Started.'), finish(:stop), job_exit, text('It passed.'), finish(:stop), turn_end)

        assert_equal "Started.\n\nIt passed.", turn.answer
      end

      it 'takes the prose of a reply that reported no finish reason as an answer' do
        assert_equal "Started.\n\nIt passed.", buffer(text('Started.'), job_exit, text('It passed.'), turn_end).answer
      end

      it 'keeps a reply whose prose is blank out of the answer' do
        assert_equal 'It passed.', buffer(text("\n"), job_exit, text('It passed.'), turn_end).answer
      end

      it 'keeps the answer before the exit when the reply to it is interrupted' do
        assert_equal "Started.\n\nHalf a sen", buffer(text('Started.'), job_exit, text('Half a sen'), interrupt).answer
      end
    end
  end

  describe '#prose' do
    it 'hands out a copy that later deltas leave alone' do
      streaming = buffer(text('Hel'))
      read = streaming.prose

      streaming.absorb(text('lo'))

      assert_equal 'Hel', read
    end
  end

  describe '#interrupted?' do
    it 'is false for a turn that ran to its end' do
      refute_predicate buffer(text('All done.'), finish(:stop), turn_end), :interrupted?
    end

    it 'is true once the turn is interrupted' do
      assert_predicate buffer(text('Half a sen'), interrupt), :interrupted?
    end
  end

  describe '#ended?' do
    it 'is false while the turn is running' do
      refute_predicate buffer(text('All done.'), finish(:stop)), :ended?
    end

    it 'is true once the turn has ended' do
      assert_predicate buffer(text('All done.'), turn_end), :ended?
    end
  end

  describe '#stats' do
    it 'returns a frozen record' do
      assert_predicate buffer.stats, :frozen?
    end

    describe 'steps' do
      it 'counts none before a request starts' do
        assert_equal 0, buffer.stats.steps
      end

      it 'counts a request as soon as its prose starts' do
        assert_equal 1, buffer(text('Hel')).stats.steps
      end

      it 'counts a request that reports only a tool call' do
        assert_equal 1, buffer(tool_call).stats.steps
      end

      it 'counts a request that reports only a finish reason' do
        assert_equal 1, buffer(finish(:stop)).stats.steps
      end

      it 'counts a request that reports only its usage' do
        assert_equal 1, buffer(usage(100, 20)).stats.steps
      end

      it 'counts a request once however many events it sends' do
        assert_equal 1, buffer(text('All '), text('done.'), finish(:stop), usage(100, 20), turn_end).stats.steps
      end

      it 'counts the request after a tool run as another step' do
        assert_equal 2, buffer(tool_call, finish(:tool_calls), tools_run, tools_run, text('Done.')).stats.steps
      end

      it 'counts none for a tool that runs before any request' do
        assert_equal 0, buffer(tools_run).stats.steps
      end

      it 'counts the reply a job exit continued the turn with as another step' do
        assert_equal 2, buffer(text('Started.'), finish(:stop), job_exit, text('Passed.'), finish(:stop)).stats.steps
      end

      it 'counts the request an interrupt cut short' do
        assert_equal 1, buffer(text('Half a sen'), interrupt, turn_end).stats.steps
      end
    end

    describe 'wall time' do
      it 'runs from construction to the moment it is read while the turn is live' do
        ticks = [10.0, 12.5]

        assert_in_delta 2.5, buffer(text('Hel'), clock: -> { ticks.shift }).stats.wall_time
      end

      it 'stops at the end of the turn' do
        ticks = [10.0, 14.0, 99.0]

        assert_in_delta 4.0, buffer(text('Done.'), turn_end, clock: -> { ticks.shift }).stats.wall_time
      end
    end

    describe 'usage' do
      it 'is absent until a request reports it' do
        assert_nil buffer(text('Hel')).stats.usage
      end

      it 'includes the request in flight' do
        assert_equal 120, buffer(text('Hel'), usage(100, 20)).stats.usage.total_tokens
      end

      it "takes the last of a request's usage readings" do
        turn = buffer(text('All '), usage(100, 4), text('done.'), usage(100, 20), finish(:stop), turn_end)

        assert_equal 120, turn.stats.usage.total_tokens
      end

      it 'counts usage reported after the finish reason' do
        assert_equal 120, buffer(text('Done.'), finish(:stop), usage(100, 20), turn_end).stats.usage.total_tokens
      end

      it 'adds the usage of each request' do
        first = [tool_call, finish(:tool_calls), usage(100, 20), tools_run]
        second = [usage(150, 4), text('Done.'), usage(150, 10), finish(:stop)]

        assert_equal 280, buffer(first, second, turn_end).stats.usage.total_tokens
      end

      it 'adds the usage of the reply a job exit continued the turn with' do
        first = [text('Started.'), finish(:stop), usage(100, 20)]
        second = [text('Passed.'), finish(:stop), usage(150, 10)]

        assert_equal 280, buffer(first, job_exit, second, turn_end).stats.usage.total_tokens
      end

      it 'keeps the usage of an interrupted turn' do
        turn = buffer(tool_call, finish(:tool_calls), usage(100, 20), before_tool, interrupt, turn_end)

        assert_equal 120, turn.stats.usage.total_tokens
      end
    end
  end

  describe "a turn of each provider's scripted streams" do
    before { @streams = ProviderStreams.new }
    after { @streams.stop }

    def turn(provider)
      buffer(@streams.events(provider, :tool_call), tools_run, @streams.events(provider, :answer), turn_end)
    end

    %i[openai anthropic gemini openrouter amazon_bedrock].each do |provider|
      it "keeps the prose of the #{provider} tool-call request as the ghost" do
        assert_equal 'Let me read the file.', turn(provider).ghost
      end

      it "keeps the prose of the #{provider} reply as the answer" do
        assert_equal 'The file is empty.', turn(provider).answer
      end

      it "counts the usage of each #{provider} request once" do
        assert_equal 280, turn(provider).stats.usage.total_tokens
      end
    end
  end

  describe 'a turn the runtime streams from the mock provider' do
    def turn
      reads = Riffer::Rig::Extension.new('reads') { |rig| rig.tool Riffer::Rig::Tools::Read }
      runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [reads])
      runtime.agent.provider.stub_response(
        'Let me read the file.',
        tool_calls: [{ name: 'read', arguments: '{"path":"notes.txt"}' }],
        token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 20)
      )
      runtime.agent.provider.stub_response(
        'The file is empty.',
        token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 150, output_tokens: 10)
      )
      buffer(runtime.prompt('What is in notes.txt?').to_a)
    end

    it 'keeps the prose of the tool-call request as the ghost' do
      assert_equal 'Let me read the file.', turn.ghost
    end

    it 'keeps the prose of the reply as the answer' do
      # The mock provider ends every delta it streams with a space.
      assert_equal 'The file is empty. ', turn.answer
    end

    it 'counts a step for each request' do
      assert_equal 2, turn.stats.steps
    end

    it 'counts the usage of each request once' do
      assert_equal 280, turn.stats.usage.total_tokens
    end
  end
end
