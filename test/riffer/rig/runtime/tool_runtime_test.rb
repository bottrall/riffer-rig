# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::Runtime::ToolRuntime do
  before do
    @echo = Class.new(Riffer::Tool) do
      identifier 'echo'
      description 'Echoes its text'

      params do
        required :text, String
      end

      define_method(:call) do |context:, text:| # rubocop:disable Lint/UnusedBlockArgument -- riffer passes context: to every call
        text == 'fail' ? error('refused') : text("echo: #{text}")
      end
    end
    @emitted = [] #: Array[Riffer::Rig::Events::_Event]
    @hooked = [] #: Array[Riffer::Rig::Events::_Event]
    @ticks = 1.0.step
  end

  def tool_runtime(**registered)
    probe = ->(event) { @hooked << event }
    all = Riffer::Rig::Registrar::EVENTS.to_h { |event| [event, registered.fetch(event, [])] }
    hooks = Riffer::Rig::Runtime::Hooks.new(
      all.merge(
        before_tool_call: [probe, *all.fetch(:before_tool_call)],
        after_tool_call: [*all.fetch(:after_tool_call), probe]
      ),
      Riffer::Rig::Hosts::Null.new
    )
    Riffer::Rig::Runtime::ToolRuntime.new(hooks, emit: ->(event) { @emitted << event }, clock: -> { @ticks.next })
  end

  def call(call_id, name: 'echo', arguments: '{"text":"hi"}')
    Riffer::Messages::Assistant::ToolCall.new(call_id: call_id, name: name, arguments: arguments)
  end

  def execute(runtime, *calls)
    runtime.execute(calls, tools: [@echo], context: nil)
  end

  def shape(events)
    events.map { |event| event.is_a?(Riffer::Rig::Events::AfterToolCall) ? [event.type, event.result.error_type] : event.type }
  end

  def blocker
    ->(_event) { [:block, 'no'] }
  end

  describe 'a call that succeeds' do
    before { execute(tool_runtime, call('a')) }

    it 'fires both hooks' do
      assert_equal [:before_tool_call, [:after_tool_call, nil]], shape(@hooked)
    end

    it 'emits both events' do
      assert_equal [:before_tool_call, [:after_tool_call, nil]], shape(@emitted)
    end

    it 'emits the after event the hook observed' do
      assert_same @hooked.last, @emitted.last
    end

    it 'carries the result on the after event' do
      assert_equal 'echo: hi', @emitted.last.result.content
    end

    it 'identifies the call on both events' do
      assert_equal([%w[a echo], %w[a echo]], @emitted.map { |event| [event.call_id, event.tool] })
    end
  end

  describe 'a call whose tool returns an error' do
    before { execute(tool_runtime, call('a', arguments: '{"text":"fail"}')) }

    it 'fires both hooks' do
      assert_equal [:before_tool_call, %i[after_tool_call execution_error]], shape(@hooked)
    end

    it 'emits both events' do
      assert_equal [:before_tool_call, %i[after_tool_call execution_error]], shape(@emitted)
    end
  end

  describe 'a call to an unknown tool' do
    before { execute(tool_runtime, call('a', name: 'missing')) }

    it 'fires both hooks' do
      assert_equal [:before_tool_call, %i[after_tool_call unknown_tool]], shape(@hooked)
    end

    it 'emits both events' do
      assert_equal [:before_tool_call, %i[after_tool_call unknown_tool]], shape(@emitted)
    end
  end

  describe 'a call a before_tool_call hook blocks' do
    before { @results = execute(tool_runtime(before_tool_call: [blocker]), call('a')) }

    it 'fires the after hook with the blocked result' do
      assert_equal [:before_tool_call, %i[after_tool_call blocked]], shape(@hooked)
    end

    it 'emits the after event alone' do
      assert_equal [%i[after_tool_call blocked]], shape(@emitted)
    end

    it 'carries the arguments the model sent' do
      assert_equal({ text: 'hi' }, @emitted.last.args)
    end

    it 'reports no time spent in the tool' do
      assert_in_delta 0.0, @emitted.last.duration
    end

    it 'returns the blocked result' do
      assert_equal(['no'], @results.map { |_tool_call, response| response.content })
    end
  end

  describe 'a call with invalid JSON arguments' do
    before { execute(tool_runtime, call('a', arguments: '{not json')) }

    it 'fires the after hook alone' do
      assert_equal [%i[after_tool_call validation_error]], shape(@hooked)
    end

    it 'emits the after event alone' do
      assert_equal [%i[after_tool_call validation_error]], shape(@emitted)
    end

    it 'carries empty arguments' do
      assert_empty @emitted.last.args
    end

    it 'reports no time spent in the tool' do
      assert_in_delta 0.0, @emitted.last.duration
    end
  end

  describe 'a call with non-object arguments' do
    before { execute(tool_runtime, call('a', arguments: '[1]')) }

    it 'fires the after hook alone' do
      assert_equal [%i[after_tool_call validation_error]], shape(@hooked)
    end

    it 'emits the after event alone' do
      assert_equal [%i[after_tool_call validation_error]], shape(@emitted)
    end

    it 'carries empty arguments' do
      assert_empty @emitted.last.args
    end

    it 'reports no time spent in the tool' do
      assert_in_delta 0.0, @emitted.last.duration
    end
  end

  describe 'timing' do
    def slow_hook
      ->(_event) { 3.times { @ticks.next } }
    end

    it 'stamps every hook of the veto chain with one clock read' do
      execute(tool_runtime(before_tool_call: [->(event) { @hooked << event }]), call('a'))

      assert_equal [1.0, 1.0], @hooked.grep(Riffer::Rig::Events::BeforeToolCall).map(&:at)
    end

    it 'starts the emitted before event once the veto chain settles' do
      execute(tool_runtime(before_tool_call: [slow_hook]), call('a'))

      assert_in_delta 5.0, @emitted.first.at
    end

    it 'finishes the after event when the tool returns' do
      execute(tool_runtime, call('a'))

      assert_in_delta 3.0, @emitted.last.at
    end

    it 'spans the two emitted events with the duration' do
      execute(tool_runtime, call('a'))

      assert_in_delta @emitted.last.at - @emitted.first.at, @emitted.last.duration
    end

    it 'leaves time spent in before_tool_call hooks out of the duration' do
      execute(tool_runtime(before_tool_call: [slow_hook]), call('a'))

      assert_in_delta 1.0, @emitted.last.duration
    end

    it 'leaves time spent in after_tool_call hooks out of the duration' do
      execute(tool_runtime(after_tool_call: [slow_hook]), call('a'))

      assert_in_delta 1.0, @emitted.last.duration
    end
  end

  describe 'a hook that rewrites the arguments' do
    before do
      rewrite = ->(event) { event.args.merge(text: 'replaced') }
      @results = execute(tool_runtime(before_tool_call: [rewrite]), call('a'))
    end

    it 'runs the tool with them' do
      assert_equal(['echo: replaced'], @results.map { |_tool_call, response| response.content })
    end

    it 'emits a single before event carrying them' do
      assert_equal [{ text: 'replaced' }], @emitted.grep(Riffer::Rig::Events::BeforeToolCall).map(&:args)
    end

    it 'carries them on the after event' do
      assert_equal({ text: 'replaced' }, @emitted.last.args)
    end
  end

  it 'runs a batch one call at a time' do
    execute(tool_runtime, call('a'), call('b'))

    assert_equal(
      [[:before_tool_call, 'a'], [:after_tool_call, 'a'], [:before_tool_call, 'b'], [:after_tool_call, 'b']],
      @emitted.map { |event| [event.type, event.call_id] }
    )
  end

  it 'fires each hook once per call' do
    execute(tool_runtime, call('a'), call('b'))

    assert_equal %i[before_tool_call after_tool_call] * 2, @hooked.map(&:type)
  end

  it 'emits the before event after the before_tool_call hooks and before the tool runs' do
    emitted_at_hook = nil
    execute(tool_runtime(before_tool_call: [->(_event) { emitted_at_hook = @emitted.dup }]), call('a'))

    assert_empty emitted_at_hook
  end

  it "returns riffer's results unchanged" do
    results = execute(tool_runtime, call('a'))

    assert_equal(['echo: hi'], results.map { |_tool_call, response| response.content })
  end

  it 'ignores what an after_tool_call hook returns' do
    results = execute(tool_runtime(after_tool_call: [->(_event) { 'IGNORED' }]), call('a'))

    assert_equal(['echo: hi'], results.map { |_tool_call, response| response.content })
  end
end
