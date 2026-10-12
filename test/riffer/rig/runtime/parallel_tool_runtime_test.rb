# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::ParallelToolRuntime do
  before do
    @log = Queue.new
    @tools = [meet_tool(@log, { 'a' => Queue.new, 'b' => Queue.new, 'c' => Queue.new })]
  end

  def meet_tool(log, arrivals)
    Class.new(Riffer::Tool) do
      identifier 'meet'
      description 'Waits for its peer'

      params do
        required :who, String
        optional :peer, String
      end

      define_method(:call) do |context:, who:, peer: nil| # rubocop:disable Lint/UnusedBlockArgument -- riffer passes context: to every call
        log << [:tool, who, Thread.current]
        arrivals.fetch(who) << true
        # The peer only arrives if its call overlaps this one.
        text(peer.nil? || arrivals.fetch(peer).pop(timeout: 5) ? 'met' : 'alone')
      end
    end
  end

  def call(who, peer = nil)
    arguments = { who: who, peer: peer }.compact.to_json
    Riffer::Messages::Assistant::ToolCall.new(call_id: who, name: 'meet', arguments: arguments)
  end

  def runtime(host: Riffer::Rig::Hosts::Null.new, **registered)
    all = Riffer::Rig::Registrar::EVENTS.to_h { |event| [event, registered.fetch(event, [])] }
    hooks = Riffer::Rig::Runtime::Hooks.new(all, host)
    Riffer::Rig::Runtime::ParallelToolRuntime.new(hooks, Riffer::Runner::Threaded.new(max_concurrency: 3))
  end

  def logging(kind)
    ->(event) { @log << [kind, event.args[:who], Thread.current] }
  end

  def logged(kind = nil)
    entries = Array.new(@log.size) { @log.pop }
    kind ? entries.select { |entry| entry.first == kind } : entries
  end

  def steps(entries)
    entries.map { |entry| entry.first(2) }
  end

  def execute(runtime, calls)
    runtime.execute(calls, tools: @tools, context: nil)
  end

  def responses(runtime, calls)
    execute(runtime, calls).map(&:last)
  end

  it 'runs the approved calls at the same time' do
    assert_equal %w[met met], responses(runtime, [call('a', 'b'), call('b', 'a')]).map(&:content)
  end

  it 'runs the tools off the calling thread' do
    execute(runtime, [call('a'), call('b')])

    refute_includes logged.map(&:last), Thread.current
  end

  it 'returns the results in call order' do
    calls = [call('a', 'b'), call('b', 'c'), call('c', 'a')]

    assert_equal calls, execute(runtime, calls).map(&:first)
  end

  it 'runs every veto in call order before any tool starts' do
    execute(runtime(before_tool_call: [logging(:before)]), [call('a'), call('b'), call('c')])

    assert_equal [[:before, 'a'], [:before, 'b'], [:before, 'c']], steps(logged.first(3))
  end

  it 'runs the vetoes on the calling thread' do
    execute(runtime(before_tool_call: [logging(:before)]), [call('a'), call('b'), call('c')])

    assert_equal [Thread.current], logged(:before).map(&:last).uniq
  end

  it 'runs every after_tool_call hook in call order once the tools finish' do
    execute(runtime(after_tool_call: [logging(:after)]), [call('a', 'b'), call('b', 'c'), call('c', 'a')])

    assert_equal [[:after, 'a'], [:after, 'b'], [:after, 'c']], steps(logged.last(3))
  end

  it 'runs the after_tool_call hooks on the calling thread' do
    execute(runtime(after_tool_call: [logging(:after)]), [call('a'), call('b'), call('c')])

    assert_equal [Thread.current], logged(:after).map(&:last).uniq
  end

  it 'reports a failing hook on the calling thread' do
    threads = []
    host = Riffer::Rig::Hosts::Null.new
    host.define_singleton_method(:notify) { |*, **| threads << Thread.current }
    execute(runtime(host: host, after_tool_call: [->(_event) { raise 'boom' }]), [call('a'), call('b')])

    assert_equal [Thread.current], threads.uniq
  end

  describe 'with a veto' do
    def vetoing(**)
      runtime(before_tool_call: [->(event) { [:block, 'not b'] if event.args[:who] == 'b' }], **)
    end

    it 'answers the blocked call in its own position' do
      answers = responses(vetoing, [call('a'), call('b'), call('c')])

      assert_equal [nil, :blocked, nil], answers.map(&:error_type)
    end

    it 'carries the reason on the blocked call' do
      assert_equal 'not b', responses(vetoing, [call('a'), call('b'), call('c')])[1].error_message
    end

    it 'never runs the blocked tool' do
      execute(vetoing, [call('a'), call('b'), call('c')])

      assert_equal %w[a c], logged(:tool).map { |entry| entry[1] }.sort
    end

    it 'still runs the calls around a blocked one at the same time' do
      answers = responses(vetoing, [call('a', 'c'), call('b'), call('c', 'a')])

      assert_equal %w[met met], answers.values_at(0, 2).map(&:content)
    end

    it 'fires no after_tool_call hook for the blocked call' do
      execute(vetoing(after_tool_call: [logging(:after)]), [call('a'), call('b')])

      assert_equal [[:after, 'a']], steps(logged(:after))
    end

    it 'returns only blocked results when every call is vetoed' do
      answers = responses(runtime(before_tool_call: [->(_event) { :block }]), [call('a'), call('b')])

      assert_equal %i[blocked blocked], answers.map(&:error_type)
    end
  end

  describe 'with a replacement payload' do
    def rewriting(**)
      runtime(before_tool_call: [->(event) { event.args.merge(who: 'c') }], **)
    end

    it 'runs the tool with the replacement' do
      execute(rewriting, [call('a')])

      assert_equal [[:tool, 'c']], steps(logged)
    end

    it 'hands after_tool_call the args as run' do
      execute(rewriting(after_tool_call: [logging(:after)]), [call('a')])

      assert_equal [[:after, 'c']], steps(logged(:after))
    end

    it "returns the model's own call" do
      original = call('a')

      assert_same original, execute(rewriting, [original]).first.first
    end
  end

  describe 'with arguments that are not a JSON object' do
    def malformed(arguments)
      Riffer::Messages::Assistant::ToolCall.new(call_id: 'x', name: 'meet', arguments: arguments)
    end

    it 'answers unparseable arguments with a validation error' do
      assert_equal :validation_error, responses(runtime, [malformed('{not json')]).first.error_type
    end

    it 'answers a non-object with a validation error' do
      assert_equal :validation_error, responses(runtime, [malformed('[1]')]).first.error_type
    end

    it 'shows the call to no hook' do
      execute(runtime(before_tool_call: [logging(:before)], after_tool_call: [logging(:after)]), [malformed('[1]')])

      assert_empty logged
    end
  end
end
