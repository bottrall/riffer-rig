# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'stringio'
require_relative '../../support/host_namespace'
require_relative '../../support/stdin_pipes'

class ScriptedRuntime
  attr_reader :cancelled, :timeouts, :follow_ups

  def initialize(events, exits: [], follow_up: [], &before_events)
    @events = events
    @exits = exits.dup
    @follow_up = follow_up
    @before_events = before_events
    @cancelled = Queue.new
    @closed = false
    @timeouts = []
    @follow_ups = 0
  end

  def prompt(_text, &)
    @before_events&.call(self)
    @events.each(&)
  end

  def pending_jobs?
    !@exits.empty?
  end

  def await_job_exit(timeout: nil)
    @timeouts << timeout
    exit = @exits.shift
    exit.is_a?(Class) ? raise(exit) : exit
  end

  def follow_up(&)
    @follow_ups += 1
    @follow_up.each(&)
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
  include HostNamespace
  include StdinPipes

  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
    @output = StringIO.new
    @error = StringIO.new
  end

  after do
    close_pipes
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
    stdin_timeout: Riffer::Rig::Headless::STDIN_TIMEOUT,
    &block
  )
    input = piped(input) if input.is_a?(String)
    @status = Riffer::Rig::Headless.for(
      input: input, output: @output, error: @error, verbose: verbose, json: json, stdin_timeout: stdin_timeout
    ).run(prompt: prompt) do |host|
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
    @status = Riffer::Rig::Headless.for(input: piped(input), output: @output, error: @error).run(
      prompt: prompt
    ) do |host|
      @runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [extension], host: host, cwd: @cwd)
      yield @runtime
      @runtime
    end
  end

  def run_build(json: false, job_idle_timeout: Riffer::Rig::Headless::JOB_IDLE_TIMEOUT, &)
    @status = Riffer::Rig::Headless.for(
      input: piped(''), output: @output, error: @error, json: json, job_idle_timeout: job_idle_timeout
    ).run(prompt: 'hello', &)
  end

  def run_scripted(*events, &)
    @runtime = ScriptedRuntime.new(events, &)
    run_build { @runtime }
  end

  def turn_end(stop_reason)
    Riffer::Rig::Events::TurnEnd.new(stop_reason, nil)
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

  def run_waiting(exits, events: [turn_end(:completed)], follow_up: [turn_end(:completed)], **)
    @runtime = ScriptedRuntime.new(events, exits: exits, follow_up: follow_up)
    run_build(**) { @runtime }
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

  it 'strips whitespace around the prompt argument' do
    run_headless(prompt: "  review this\n", input: 'the diff') { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal "review this\n\nthe diff", prompt_sent_to_model
  end

  it 'uses piped stdin alone as the prompt without an argument' do
    run_headless(input: 'the diff') { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal 'the diff', prompt_sent_to_model
  end

  it 'replaces invalid UTF-8 in piped stdin' do
    run_headless(prompt: 'review this', input: "caf\xE9") { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal "review this\n\ncaf\uFFFD", prompt_sent_to_model
  end

  it 'never reads a TTY stdin' do
    input = StringIO.new('piped content')
    input.define_singleton_method(:tty?) { true }

    run_headless(prompt: 'hello', input: input) { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal 'hello', prompt_sent_to_model
  end

  it 'waits on stdin past the timeout without a prompt argument' do
    reader, writer = pipe
    main = Thread.current
    feeder = Thread.new do
      Thread.pass until main.stop?
      writer.write('the diff')
      writer.close
    end

    run_headless(input: reader, stdin_timeout: 0) { |runtime| runtime.agent.provider.stub_response('Hi') }
    feeder.kill

    assert_equal 'the diff', prompt_sent_to_model
  end

  it 'reads a stdin closed with no data without a warning' do
    run_headless(prompt: 'hello', input: '') { |runtime| runtime.agent.provider.stub_response('Hi') }

    refute_includes @error.string, 'no stdin data'
  end

  it 'warns when stdin sends nothing within the timeout' do
    run_headless(prompt: 'hello', input: pipe.first, stdin_timeout: 0) do |runtime|
      runtime.agent.provider.stub_response('Hi')
    end

    assert_match(
      %r{no stdin data received in 0s, proceeding without it; redirect stdin from /dev/null to skip this},
      @error.string
    )
  end

  it 'proceeds with the prompt argument alone when stdin sends nothing within the timeout' do
    run_headless(prompt: 'hello', input: pipe.first, stdin_timeout: 0) do |runtime|
      runtime.agent.provider.stub_response('Hi')
    end

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

  it 'returns two when the prompt argument is only whitespace' do
    run_headless(prompt: '   ')

    assert_equal 2, @status
  end

  it 'returns two when piped stdin is only whitespace' do
    run_headless(input: "  \n ")

    assert_equal 2, @status
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

  describe 'with background jobs' do
    it 'never waits without a job' do
      run_waiting([])

      assert_empty @runtime.timeouts
    end

    it 'never waits after a turn that did not complete' do
      run_waiting([true], events: [turn_end(:max_steps)])

      assert_empty @runtime.timeouts
    end

    it 'says on stderr that it is waiting' do
      run_waiting([true])

      assert_match(/waiting for background jobs/, @error.string)
    end

    it 'has written the reply through to a pipe by the time it waits' do
      reader, @output = IO.pipe
      @output.sync = false
      seen = nil
      reply = Riffer::StreamEvents::TextDone.new('started')
      @runtime = ScriptedRuntime.new([reply, turn_end(:completed)], exits: [false])
      @runtime.define_singleton_method(:await_job_exit) do |**|
        seen = reader.read_nonblock(64, exception: false)
        false
      end
      run_build { @runtime }
      [@output, reader].each(&:close)

      assert_equal "started\n", seen
    end

    it 'waits for an exit with the idle timeout' do
      run_waiting([true], job_idle_timeout: 30)

      assert_equal [30], @runtime.timeouts
    end

    it 'waits for an exit without a timeout when the idle timeout is zero' do
      run_waiting([true], job_idle_timeout: 0)

      assert_equal [nil], @runtime.timeouts
    end

    it 'returns 130 when interrupted while waiting' do
      run_waiting([Interrupt])

      assert_equal 130, @status
    end

    it 'says it is killing the jobs once the idle timeout passes' do
      run_waiting([false], job_idle_timeout: 30)

      assert_match(/no background job exited in 30s; killing the jobs still running/, @error.string)
    end

    it 'returns three once the idle timeout passes' do
      run_waiting([false])

      assert_equal 3, @status
    end

    it 'closes the runtime once the idle timeout passes' do
      run_waiting([false])

      assert_predicate @runtime, :closed?
    end

    it 'follows up once for each exit' do
      run_waiting([true, true])

      assert_equal 2, @runtime.follow_ups
    end

    it 'prints the reply of a follow-up' do
      run_waiting([true], follow_up: [Riffer::StreamEvents::TextDone.new('It passed.'), turn_end(:completed)])

      assert_equal "It passed.\n", @output.string
    end

    it 'separates the reply of a follow-up from the turn before with a blank line' do
      run_waiting(
        [true],
        events: [Riffer::StreamEvents::TextDone.new('started'), turn_end(:completed)],
        follow_up: [job_exit, Riffer::StreamEvents::TextDone.new('It passed.'), turn_end(:completed)]
      )

      assert_equal "started\n\nIt passed.\n", @output.string
    end

    it 'prints the blank line only once for a follow-up that streams its reply' do
      run_waiting(
        [true],
        events: [Riffer::StreamEvents::TextDone.new('started'), turn_end(:completed)],
        follow_up: [
          job_exit,
          Riffer::StreamEvents::TextDelta.new('It '),
          Riffer::StreamEvents::TextDelta.new('passed.'),
          Riffer::StreamEvents::TextDone.new('It passed.'),
          turn_end(:completed)
        ]
      )

      assert_equal "started\n\nIt passed.\n", @output.string
    end

    it 'prints no blank line for a follow-up that prints nothing' do
      run_waiting(
        [true],
        events: [Riffer::StreamEvents::TextDone.new('started'), turn_end(:completed)],
        follow_up: [job_exit, turn_end(:completed)]
      )

      assert_equal "started\n", @output.string
    end

    it 'separates the reply a job exit continued the turn with from the reply before with a blank line' do
      run_scripted(
        Riffer::StreamEvents::TextDone.new('started'),
        job_exit,
        Riffer::StreamEvents::TextDone.new('It passed.'),
        turn_end(:completed)
      )

      assert_equal "started\n\nIt passed.\n", @output.string
    end

    it 'prints no blank line before the reply to a job exit when no text came before it' do
      run_scripted(job_exit, Riffer::StreamEvents::TextDone.new('It passed.'), turn_end(:completed))

      assert_equal "It passed.\n", @output.string
    end

    it 'returns the code of the last follow-up' do
      run_waiting([true, true], follow_up: [turn_end(:max_steps)])

      assert_equal 3, @status
    end

    it 'gives the model a further turn with the exit of a job it left running' do
      run_headless(prompt: 'start it') do |runtime|
        start = { command: 'sleep 0.2', run_in_background: true }.to_json
        runtime.agent.provider.stub_response('', tool_calls: [{ name: 'bash', arguments: start }])
        runtime.agent.provider.stub_response('Waiting.')
        runtime.agent.provider.stub_response('It finished.')
      end

      assert_includes @output.string, 'It finished.'
    end
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

  it 'says what the provider answered when the turn raises a provider error' do
    error = StandardError.new('status=400').tap do |status_error|
      status_error.define_singleton_method(:body) { { error: { message: 'bad model' } } }
    end
    run_headless(prompt: 'hello') do |runtime|
      runtime.agent.provider.define_singleton_method(:stream_text) { |*| raise error }
    end

    assert_match(/riffer: status=400: bad model/, @error.string)
  end

  it 'restores the previous INT handler after the turn' do
    handler = proc {}
    previous = Signal.trap('INT', handler)
    run_scripted
    restored = Signal.trap('INT', previous)

    assert_same handler, restored
  end

  it 'prints the session id on stderr when the session starts' do
    run_headless(prompt: 'hello') { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal "session #{@runtime.id}\n", @error.string
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

  it 'prints no tool trace without --verbose' do
    run_headless(prompt: 'read it') do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('Done.')
    end

    refute_match(/tool_call/, @error.string)
  end

  it 'traces one line per tool call on stderr with --verbose' do
    run_headless(prompt: 'read it', verbose: true) do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('Done.')
    end

    assert_match(%r{tool_call read \{"path":"/tmp/x"\}}, @error.string)
  end

  it 'traces tool calls on stderr with --json and --verbose' do
    run_headless(prompt: 'read it', verbose: true, json: true) do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('Done.')
    end

    assert_match(%r{tool_call read \{"path":"/tmp/x"\}}, @error.string)
  end

  it 'prints nothing for the tool call events in text mode' do
    run_headless(prompt: 'read it') do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('Done.')
    end

    assert_equal ["Done. \n", "session #{@runtime.id}\n"], [@output.string, @error.string]
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

    it 'keeps the session id off stderr in --json mode' do
      run_headless(prompt: 'hello', json: true) { |runtime| runtime.agent.provider.stub_response('Hi') }

      assert_empty @error.string
    end

    it 'carries the session id on the session_start record' do
      run_headless(prompt: 'hello', json: true) { |runtime| runtime.agent.provider.stub_response('Hi') }

      session_start = records.find { |record| record.fetch('type') == 'session_start' }

      assert_equal @runtime.id, session_start.fetch('id')
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

    it 'keeps the waiting note off stdout' do
      run_waiting([true], json: true)

      refute_match(/waiting/, @output.string)
    end

    it 'prints a warning record once the idle timeout passes' do
      run_waiting([false], json: true, job_idle_timeout: 30)

      assert_equal(
        {
          'type' => 'notify',
          'message' => 'no background job exited in 30s; killing the jobs still running',
          'level' => 'warning'
        },
        records.last
      )
    end

    it 'prints no blank line between the records of a follow-up' do
      run_waiting(
        [true],
        json: true,
        events: [Riffer::StreamEvents::TextDone.new('started'), turn_end(:completed)],
        follow_up: [Riffer::StreamEvents::TextDone.new('It passed.'), turn_end(:completed)]
      )

      refute_match(/\n\n/, @output.string)
    end

    it 'prints no blank line between the records around a job exit within a turn' do
      run_build(json: true) do
        ScriptedRuntime.new(
          [
            Riffer::StreamEvents::TextDone.new('started'),
            job_exit,
            Riffer::StreamEvents::TextDone.new('It passed.'),
            turn_end(:completed)
          ]
        )
      end

      refute_match(/\n\n/, @output.string)
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

  describe '#refuse' do
    def refuse(json: false)
      headless = Riffer::Rig::Headless.for(input: StringIO.new, output: @output, error: @error, json: json)
      @status = headless.refuse('gone')
    end

    it 'prints the message on stderr' do
      refuse

      assert_equal "riffer: gone\n", @error.string
    end

    it 'prints the message as an error record with --json' do
      refuse(json: true)

      assert_equal({ 'type' => 'error', 'message' => 'gone' }, JSON.parse(@output.string))
    end

    it 'returns two' do
      refuse

      assert_equal 2, @status
    end
  end

  describe 'namespace' do
    it 'references no Riffer::Rig constant outside the public host API' do
      assert_empty rig_constants_outside('Headless') - %w[
        Events::_Event
        Events::JobExit
        Events::Notify
        Events::SessionStart
        Events::TurnEnd
        Hosts::_Host
        Hosts::NonInteractive
        Loader::ConfigurationError
        Runtime
        Runtime::ErrorMessage
        Runtime::INTERRUPT_CANCELLED
        Runtime::STOPPED_WITHOUT_COMPLETING
      ]
    end
  end
end
