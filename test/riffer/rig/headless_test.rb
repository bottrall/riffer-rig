# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'stringio'

class ScriptedRuntime
  attr_reader :cancelled

  def initialize(events, &before_events)
    @events = events
    @before_events = before_events
    @cancelled = Queue.new
    @closed = false
  end

  def prompt(_text, &)
    @before_events&.call(self)
    @events.each(&)
  end

  def cancel
    @cancelled << true
  end

  def close
    @closed = true
  end

  def closed?
    @closed
  end
end

describe Riffer::Rig::Headless do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @output = StringIO.new
    @error = StringIO.new
  end

  after do
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def run_headless(
    prompt: nil,
    input: '',
    env: { 'MOCK_API_KEY' => 'mock-key' },
    model: 'mock/test',
    verbose: false,
    json: false,
    max_steps: nil,
    &block
  )
    input = StringIO.new(input) if input.is_a?(String)
    @status = Riffer::Rig::Headless.for(input: input, output: @output, error: @error, verbose: verbose, json: json).run(
      prompt: prompt
    ) do |host|
      @runtime = Riffer::Rig::Loader.runtime(
        cwd: @cwd,
        host: host,
        env: Riffer::Rig::Env.new(env),
        home: @home,
        riffer_config: Riffer::Config.new,
        options: Riffer::Rig::Loader::Options.new(model: model, max_steps: max_steps)
      )
      yield @runtime if block
      @runtime
    end
  end

  def run_with_extension(extension, prompt: 'hello', input: '')
    @status = Riffer::Rig::Headless.for(input: StringIO.new(input), output: @output, error: @error).run(
      prompt: prompt
    ) do |host|
      @runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [extension], host: host, cwd: @cwd)
      yield @runtime
      @runtime
    end
  end

  def run_build(&)
    @status = Riffer::Rig::Headless.for(input: StringIO.new, output: @output, error: @error).run(prompt: 'hello', &)
  end

  def run_scripted(*events, &)
    @runtime = ScriptedRuntime.new(events, &)
    run_build { @runtime }
  end

  def interrupt_once(cancelled)
    fired = false
    Riffer::Rig::Extension.new('interrupter') do |rig|
      rig.on(:stream) do
        next if fired

        fired = true
        Process.kill('INT', Process.pid)
        cancelled.pop(timeout: 5)
      end
    end
  end

  def prompt_sent_to_model
    @runtime.agent.provider.calls.first[:messages].last[:content]
  end

  it 'prints a notify on stderr' do
    run_headless(prompt: 'hello') do |runtime|
      runtime.host.notify('heads up', level: :warning)
      runtime.agent.provider.stub_response('Hi')
    end

    assert_match(/heads up/, @error.string)
  end

  it 'keeps a notify off stdout' do
    run_headless(prompt: 'hello') do |runtime|
      runtime.host.notify('heads up', level: :warning)
      runtime.agent.provider.stub_response('Hi')
    end

    refute_match(/heads up/, @output.string)
  end

  it 'sends the prompt argument to the model' do
    run_headless(prompt: 'hello') { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal 'hello', prompt_sent_to_model
  end

  it 'appends piped stdin to the prompt argument' do
    run_headless(prompt: 'review this', input: 'the diff') { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal "review this\n\nthe diff", prompt_sent_to_model
  end

  it 'uses piped stdin alone as the prompt without an argument' do
    run_headless(input: 'the diff') { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal 'the diff', prompt_sent_to_model
  end

  it 'never reads a TTY stdin' do
    input = StringIO.new('piped content')
    input.define_singleton_method(:tty?) { true }

    run_headless(prompt: 'hello', input: input) { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal 'hello', prompt_sent_to_model
  end

  it 'returns two when there is no prompt to run' do
    run_headless

    assert_equal 2, @status
  end

  it 'says there is no prompt when there is none' do
    run_headless

    assert_match(/no prompt/, @error.string)
  end

  it 'returns two without the provider credentials' do
    run_headless(prompt: 'hello', model: 'gemini/gem-2.5-pro', env: {})

    assert_equal 2, @status
  end

  it 'names the provider recipe for a missing credential' do
    run_headless(prompt: 'hello', model: 'gemini/gem-2.5-pro', env: {})

    assert_match(/gemini has no api_key \(GEMINI_API_KEY\)/, @error.string)
  end

  it 'returns 130 when the build is interrupted' do
    run_build { raise Interrupt }

    assert_equal 130, @status
  end

  it 'returns one when the build raises' do
    run_build { raise 'no runtime' }

    assert_equal 1, @status
  end

  it 'says what raised when the build raises' do
    run_build { raise 'no runtime' }

    assert_match(/riffer: no runtime/, @error.string)
  end

  it 'closes the runtime after the turn' do
    run_scripted

    assert_predicate @runtime, :closed?
  end

  it 'closes the runtime when the turn raises' do
    run_scripted { raise 'boom' }

    assert_predicate @runtime, :closed?
  end

  it 'cancels the runtime when interrupted mid-turn' do
    cancelled = nil
    run_scripted do |runtime|
      Process.kill('INT', Process.pid)
      cancelled = runtime.cancelled.pop(timeout: 5)
    end

    assert cancelled
  end

  it 'returns one when the turn raises' do
    run_headless(prompt: 'hello') do |runtime|
      runtime.agent.provider.define_singleton_method(:stream_text) { |*| raise 'boom' }
    end

    assert_equal 1, @status
  end

  it 'says what raised when the turn raises' do
    run_headless(prompt: 'hello') do |runtime|
      runtime.agent.provider.define_singleton_method(:stream_text) { |*| raise 'boom' }
    end

    assert_match(/boom/, @error.string)
  end

  it 'restores the previous INT handler after the turn' do
    handler = proc {}
    previous = Signal.trap('INT', handler)
    run_scripted
    restored = Signal.trap('INT', previous)

    assert_same handler, restored
  end

  it 'prints only the streamed reply on stdout' do
    run_headless(prompt: 'hello') { |runtime| runtime.agent.provider.stub_response('Hi from the model') }

    assert_includes @output.string, 'Hi from the model'
  end

  it 'ends the output with a newline' do
    run_headless(prompt: 'hello') { |runtime| runtime.agent.provider.stub_response('Hi from the model') }

    assert_match(/\n\z/, @output.string)
  end

  it 'prints the whole text of a reply that was not streamed' do
    run_scripted(Riffer::StreamEvents::TextDone.new('whole reply'))

    assert_equal "whole reply\n", @output.string
  end

  it 'prints nothing for an empty reply that was not streamed' do
    run_scripted(Riffer::StreamEvents::TextDone.new(''))

    assert_empty @output.string
  end

  it 'prints an unstreamed reply that follows a streamed one' do
    run_scripted(
      Riffer::StreamEvents::TextDelta.new('first'),
      Riffer::StreamEvents::TextDone.new('first'),
      Riffer::StreamEvents::TextDone.new('second')
    )

    assert_equal "first\nsecond\n", @output.string
  end

  it 'traces one line per tool call on stderr with --verbose' do
    run_headless(prompt: 'read it', verbose: true) do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('Done.')
    end

    assert_match(%r{tool_call read \{"path":"/tmp/x"\}}, @error.string)
  end

  it 'prints no tool trace without --verbose' do
    run_headless(prompt: 'read it') do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('Done.')
    end

    refute_match(/tool_call/, @error.string)
  end

  it 'prints nothing for the tool call events in text mode' do
    run_headless(prompt: 'read it') do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('Done.')
    end

    assert_equal ["Done. \n", ''], [@output.string, @error.string]
  end

  it 'returns zero for a completed turn' do
    run_headless(prompt: 'hello') { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal 0, @status
  end

  it 'says the turn ended with the stop reason when it did not complete' do
    run_headless(prompt: 'go', max_steps: 1) do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('second response')
    end

    assert_match(/turn ended: max_steps/, @error.string)
  end

  it 'says nothing about the stop reason when the turn never ended' do
    run_scripted

    assert_empty @error.string
  end

  it 'returns 130 when interrupted and the turn is cancelled' do
    cancelled = Queue.new
    run_with_extension(interrupt_once(cancelled)) do |runtime|
      runtime.define_singleton_method(:cancel) { super().tap { cancelled << true } }
      runtime.agent.provider.stub_response('Hi')
    end

    assert_equal 130, @status
  end

  it 'returns three when the turn hits max_steps' do
    run_headless(prompt: 'go', max_steps: 1) do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('second response')
    end

    assert_equal 3, @status
  end

  it 'returns one for a provider stop reason that is not completion' do
    run_headless(prompt: 'hello') { |runtime| runtime.agent.provider.stub_response('nope', finish_reason: :error) }

    assert_equal 1, @status
  end

  it 'returns one when the turn never ended' do
    run_scripted

    assert_equal 1, @status
  end

  describe 'with --json' do
    def records
      @output.string.lines.map { |line| JSON.parse(line) }
    end

    def types
      records.map { |record| record.fetch('type') }
    end

    def turn(prompt = 'read it')
      run_headless(prompt: prompt, json: true) do |runtime|
        runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
        runtime.agent.provider.stub_response('Done.')
      end
    end

    it 'prints a notify as an event line rather than stderr' do
      run_headless(prompt: 'hello', json: true) do |runtime|
        runtime.host.notify('heads up', level: :warning)
        runtime.agent.provider.stub_response('Hi')
      end

      assert_equal(
        { 'type' => 'notify', 'message' => 'heads up', 'level' => 'warning' },
        records.find { |record| record.fetch('type') == 'notify' }
      )
    end

    it 'keeps the stderr silent for a notify in --json mode' do
      run_headless(prompt: 'hello', json: true) do |runtime|
        runtime.host.notify('heads up', level: :warning)
        runtime.agent.provider.stub_response('Hi')
      end

      assert_empty @error.string
    end

    it 'prints a single error record without a prompt' do
      run_headless(json: true)

      assert_equal ['error'], types
    end

    it 'says there is no prompt on the error record' do
      run_headless(json: true)

      assert_match(/no prompt/, records.first.fetch('message'))
    end

    it 'exits two without a prompt' do
      run_headless(json: true)

      assert_equal 2, @status
    end

    it 'prints a single error record for a configuration error' do
      run_headless(prompt: 'hello', json: true, model: 'gemini/gem-2.5-pro', env: {})

      assert_equal ['error'], types
    end

    it 'carries the reason on the configuration error record' do
      run_headless(prompt: 'hello', json: true, model: 'gemini/gem-2.5-pro', env: {})

      assert_match(/gemini has no api_key/, records.first.fetch('message'))
    end

    it 'exits two for a configuration error' do
      run_headless(prompt: 'hello', json: true, model: 'gemini/gem-2.5-pro', env: {})

      assert_equal 2, @status
    end

    it 'ends with a turn_end record' do
      turn

      assert_equal 'turn_end', types.last
    end

    it 'carries the stop reason on turn_end' do
      turn('hello')

      assert_equal 'completed', records.last.fetch('stop_reason')
    end

    it 'ends with an error record when the turn raises' do
      run_headless(prompt: 'hello', json: true) do |runtime|
        runtime.agent.provider.define_singleton_method(:stream_text) { |*| raise 'boom' }
      end

      assert_equal 'error', types.last
    end

    it 'carries the message on the error record' do
      run_headless(prompt: 'hello', json: true) do |runtime|
        runtime.agent.provider.define_singleton_method(:stream_text) { |*| raise 'boom' }
      end

      assert_equal 'boom', records.last.fetch('message')
    end

    it 'exits one when the turn raises' do
      run_headless(prompt: 'hello', json: true) do |runtime|
        runtime.agent.provider.define_singleton_method(:stream_text) { |*| raise 'boom' }
      end

      assert_equal 1, @status
    end

    it 'streams the provider stream events in order' do
      turn

      stream_events = %w[tool_call_delta tool_call_done text_done text_delta]

      assert_equal stream_events, types.intersection(stream_events)
    end

    it 'parses every line as JSON' do
      turn

      assert_equal @output.string.lines.size, records.size
    end
  end
end
