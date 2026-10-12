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
  end

  def tool_runtime(ticks: 1.0.step, **registered)
    all = Riffer::Rig::Registrar::EVENTS.to_h { |event| [event, registered.fetch(event, [])] }
    hooks = Riffer::Rig::Runtime::Hooks.new(all, Riffer::Rig::Hosts::Null.new)
    Riffer::Rig::Runtime::ToolRuntime.new(hooks, emit: ->(event) { @emitted << event }, clock: -> { ticks.next })
  end

  def call(call_id, name: 'echo', arguments: '{"text":"hi"}')
    Riffer::Messages::Assistant::ToolCall.new(call_id: call_id, name: name, arguments: arguments)
  end

  def execute(runtime, *calls)
    runtime.execute(calls, tools: [@echo], context: nil)
  end

  def outcome
    @emitted.drop(1).map { |event| event.is_a?(Riffer::Rig::Events::ToolDone) ? [event.type, event.error] : event.type }
  end

  it 'dispatches the whole batch before running each call to completion in turn' do
    execute(tool_runtime, call('a'), call('b'))

    assert_equal(
      [[:tool_dispatched, 'a'], [:tool_dispatched, 'b'],
       [:tool_running, 'a'], [:tool_done, 'a'], [:tool_running, 'b'], [:tool_done, 'b']],
      @emitted.map { |event| [event.type, event.call_id] }
    )
  end

  it 'stamps a dispatched call with the clock' do
    execute(tool_runtime(ticks: [1.5, 2.0, 4.5].each), call('a'))

    assert_equal Riffer::Rig::Events::ToolDispatched.new('a', 'echo', 1.5), @emitted.first
  end

  it 'stamps a running call with the clock' do
    execute(tool_runtime(ticks: [1.5, 2.0, 4.5].each), call('a'))

    assert_equal Riffer::Rig::Events::ToolRunning.new('a', 'echo', 2.0), @emitted[1]
  end

  it 'times a done call from running to done' do
    execute(tool_runtime(ticks: [1.5, 2.0, 4.5].each), call('a'))

    assert_equal Riffer::Rig::Events::ToolDone.new('a', 'echo', 4.5, 2.5, false), @emitted.last
  end

  it 'emits running before the tool starts' do
    seen = nil
    probe = ->(_event) { seen = @emitted.map(&:type) }
    execute(tool_runtime(before_tool_call: [probe]), call('a'))

    assert_equal %i[tool_dispatched tool_running], seen
  end

  it 'finishes a call whose tool returned an error as an error' do
    execute(tool_runtime, call('a', arguments: '{"text":"fail"}'))

    assert_equal [:tool_running, [:tool_done, true]], outcome
  end

  it 'finishes a call to an unknown tool as an error' do
    execute(tool_runtime, call('a', name: 'missing'))

    assert_equal [:tool_running, [:tool_done, true]], outcome
  end

  it 'finishes a call with invalid JSON arguments as an error' do
    execute(tool_runtime, call('a', arguments: '{not json'))

    assert_equal [:tool_running, [:tool_done, true]], outcome
  end

  it 'finishes a call with non-object arguments as an error' do
    execute(tool_runtime, call('a', arguments: '[1]'))

    assert_equal [:tool_running, [:tool_done, true]], outcome
  end

  it 'finishes a call a before_tool_call hook blocked as an error' do
    execute(tool_runtime(before_tool_call: [->(_event) { [:block, 'no'] }]), call('a'))

    assert_equal [:tool_running, [:tool_done, true]], outcome
  end

  it "returns riffer's results unchanged" do
    results = execute(tool_runtime, call('a'))

    assert_equal(['echo: hi'], results.map { |_tool_call, response| response.content })
  end
end
