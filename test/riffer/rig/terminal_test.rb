# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'stringio'
require_relative '../../support/terminal_pty'

# Delegates to the real sessions collaborator and hands each built Runtime to
# the block, so tests can stub the provider before the REPL reads a prompt.
class PreparedSessions
  def initialize(sessions, &prepare)
    @sessions = sessions
    @prepare = prepare
  end

  def find(host)
    prepare(@sessions.find(host))
  end

  def fresh(host)
    prepare(@sessions.fresh(host))
  end

  def resume(host, id)
    prepare(@sessions.resume(host, id))
  end

  def recorded(id)
    @sessions.recorded(id)
  end

  def list(host, all: false)
    @sessions.list(host, all: all)
  end

  def off
    @sessions.off
  end

  def asked?
    @sessions.asked?
  end

  def missing(id = nil)
    @sessions.missing(id)
  end

  def delete(host, id)
    @sessions.delete(host, id)
  end

  private

  def prepare(runtime)
    @prepare.call(runtime) if runtime
    runtime
  end
end

describe Riffer::Rig::Terminal do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
  end

  after do
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def cli_sessions(env: { 'MOCK_API_KEY' => 'mock-key' }, resume: nil)
    Riffer::Rig::CLI::Sessions.new(
      flags: Riffer::Rig::CLI::Flags.new(model: 'mock/test', resume: resume),
      env: Riffer::Rig::Env.new(env),
      cwd: @cwd,
      home: @home
    )
  end

  # Sessions whose `asked?` raises: the opening consults it alone, so a raise
  # there stands in for a Ctrl-C delivered in the banner.
  def interrupting_sessions
    sessions = cli_sessions
    sessions.define_singleton_method(:asked?) { raise Interrupt }
    sessions
  end

  def run_terminal(
    input,
    env: { 'MOCK_API_KEY' => 'mock-key' },
    open_picker: false,
    sessions: nil,
    &
  )
    output = StringIO.new
    input = StringIO.new(input) if input.is_a?(String)
    sessions ||= cli_sessions(env: env)
    sessions = PreparedSessions.new(sessions, &) if block_given?
    terminal = Riffer::Rig::Terminal.for(input: input, output: output, version: '9.9.9', sessions: sessions)
    @status = terminal.run(open_picker: open_picker)
    output.string
  end

  def run_on_pty(
    script,
    env: { 'MOCK_API_KEY' => 'mock-key' },
    columns: 80,
    open_picker: false,
    resume: nil,
    sessions: nil,
    &prepare
  )
    sessions ||= cli_sessions(env: env, resume: resume)
    sessions = PreparedSessions.new(sessions, &prepare) if prepare
    TerminalPty.drive(script, columns: columns) do |tty|
      terminal = Riffer::Rig::Terminal.for(
        input: tty,
        output: tty,
        version: '9.9.9',
        sessions: sessions,
        no_color: true
      )
      @status = terminal.run(open_picker: open_picker)
    end
  end

  def hold_turns(runtime, started, release)
    runtime.agent.provider.define_singleton_method(:stream_text) do |*args, **options, &block|
      started << true
      # Stands in for the provider read a cancel aborts.
      release.pop(timeout: TerminalPty::TIMEOUT_SECONDS)
      super(*args, **options, &block)
    end
  end

  def run_with_extension(input, source, &)
    dir = File.join(@home, '.riffer')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'rig.rb'), source)
    run_terminal(input, &)
  end

  def run_with_interrupter(input)
    run_terminal(input) do |runtime|
      fired = false
      runtime.agent.provider.define_singleton_method(:stream_text) do |*args, **options, &block|
        unless fired
          fired = true
          Process.kill('INT', Process.pid)
          # Stands in for the provider read the cancel aborts.
          Queue.new.pop(timeout: 5)
        end
        super(*args, **options, &block)
      end
      yield runtime if block_given?
    end
  end

  def write_skill(name)
    dir = File.join(@cwd, '.agents', 'skills', name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'SKILL.md'), "---\nname: #{name}\ndescription: Skill #{name}.\n---\nDo #{name}.\n")
  end

  def seed_runtime(cwd)
    Riffer::Rig::Loader.runtime(
      cwd: cwd,
      host: Riffer::Rig::Hosts::Null.new,
      env: Riffer::Rig::Env.new('MOCK_API_KEY' => 'mock-key'),
      home: @home,
      riffer_config: Riffer::Config.new,
      options: Riffer::Rig::Loader::Options.new(model: 'mock/test'),
      store: Riffer::Rig::Stores::JSONL.new(home: @home)
    )
  end

  def seed_session(title, cwd: @cwd, updated: Time.now)
    runtime = seed_runtime(cwd)
    runtime.prompt(title) { |event| event } # the turn only runs when its events are consumed
    runtime.close
    path = session_file_for(title, cwd: cwd)
    File.utime(updated, updated, path)
    path
  end

  def seed_history
    runtime = seed_runtime(@cwd)
    provider = runtime.agent.provider
    provider.stub_response(
      'Let me read the file.',
      tool_calls: [{ name: 'read', arguments: '{"path":"notes.txt"}' }],
      token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 100, output_tokens: 20)
    )
    provider.stub_response(
      'The file is empty.',
      token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 150, output_tokens: 30)
    )
    runtime.prompt('what is in notes.txt?') { |event| event }
    provider.stub_response(
      'Fixed it.',
      token_usage: Riffer::Providers::TokenUsage.new(input_tokens: 200, output_tokens: 40)
    )
    runtime.prompt('also fix the flaky test') { |event| event }
    runtime.close
    runtime.id
  end

  def history
    # The seeded turns are stamped by the wall clock as they run.
    first = '› what is in notes\.txt\?\r\n\r\n  The file is empty\.\r\n\r\n  2 steps · \d\d:\d\d · ↑250 · ↓50\r\n'
    second = '› also fix the flaky test\r\n\r\n  Fixed it\.\r\n\r\n  1 step · \d\d:\d\d · ↑200 · ↓40\r\n'
    /\r\n#{first}\r\n#{second}/
  end

  def session_file(id)
    session_files.find { |path| File.basename(path, '.jsonl') == id }
  end

  def rewrite_session(id)
    path = session_file(id)
    lines = yield(File.readlines(path).map { |line| JSON.parse(line) })
    File.write(path, lines.map { |line| "#{JSON.generate(line)}\n" }.join)
  end

  def session_files
    Dir.glob(File.join(@home, '.riffer', 'sessions', '*', '*.jsonl'))
  end

  def session_file_for(title, cwd:)
    session_files.find { |path| header_of(path).values_at(:cwd, :title) == [cwd, title] }
  end

  def header_of(path)
    JSON.parse(File.foreach(path).first, symbolize_names: true)
  end

  def interrupting_input(times)
    remaining = times
    input = StringIO.new
    input.define_singleton_method(:gets) do
      remaining -= 1
      raise Interrupt unless remaining.negative?
    end
    input
  end

  def scripted_input(steps)
    remaining = steps.dup
    input = StringIO.new
    input.define_singleton_method(:gets) do
      step = remaining.shift
      raise Interrupt if step == :interrupt

      step
    end
    input
  end

  it 'references no Riffer::Rig constant outside the public host API' do
    sources = [File.expand_path('../../../lib/riffer/rig/terminal.rb', __dir__),
               *Dir[File.expand_path('../../../lib/riffer/rig/terminal/**/*.rb', __dir__)]]
    referenced = sources.flat_map { |path| File.read(path).scan(/Riffer::Rig::(\w+)/).flatten }.uniq

    assert_empty referenced - %w[Terminal Runtime Hosts Loader Events Command Turn]
  end

  describe 'choosing the loop' do
    it 'runs the blocking loop when the input is not a terminal' do
      runtime = nil
      run_terminal("hello\n") { |driven| runtime = driven }

      assert_equal 1, runtime.agent.provider.calls.length
    end

    it 'runs the blocking loop when the terminal reports no width' do
      output = run_on_pty(->(pty) { pty.feed("/exit\r") }, columns: 0)

      refute_includes output, Riffer::Rig::Terminal::KeyPipeline::BRACKETED_PASTE_ON
    end

    it 'reads keys on a terminal that can draw the footer' do
      output = run_on_pty(->(pty) { pty.type("/exit\r") })

      assert_includes output, Riffer::Rig::Terminal::KeyPipeline::BRACKETED_PASTE_ON
    end
  end

  it 'returns one when the Runtime cannot be built' do
    run_terminal('', env: {})

    assert_equal 1, @status
  end

  it 'returns zero when the session ends' do
    run_terminal("/exit\n")

    assert_equal 0, @status
  end

  it 'signs off when the input ends' do
    assert_match(/see you on the next riff\.\n\z/, run_terminal(''))
  end

  describe 'when Ctrl-C was ignored at launch' do
    before { @inherited = Signal.trap('INT', 'IGNORE') }
    after { Signal.trap('INT', @inherited) }

    it 'leaves Ctrl-C ignored when the session ends' do
      run_terminal('')

      assert_equal 'IGNORE', Signal.trap('INT', 'IGNORE')
    end
  end

  describe 'bare -r' do
    it 'opens the picker before the first session' do
      path = seed_session('fix the login bug')

      run_terminal("\nhello\n", open_picker: true)

      assert_operator File.readlines(path).length, :>, 3
    end

    it 'starts fresh when the picker is dismissed' do
      assert_includes run_terminal("/exit\n", open_picker: true), 'No saved sessions.'
    end

    describe 'when the picked session is missing' do
      def run_missing_pick
        seed_session('fix the login bug')
        sessions = cli_sessions
        sessions.define_singleton_method(:resume) { |_host, _id| nil }
        sessions.define_singleton_method(:missing) { |id = nil| "wording for #{id}" }
        run_terminal("\n/exit\n", open_picker: true, sessions: sessions)
      end

      it 'takes the missing-session wording from the sessions collaborator' do
        assert_match(/wording for \S+/, run_missing_pick)
      end

      it 'notifies below the banner' do
        assert_match(%r{type /help for commands, /exit to quit.*wording for}m, run_missing_pick)
      end
    end
  end

  describe 'a session asked for with -r or -c' do
    it 'starts fresh when the asked session is missing' do
      runtime = nil
      run_terminal("/exit\n", sessions: cli_sessions(resume: 'nope')) { |driven| runtime = driven }

      assert_instance_of Riffer::Rig::Runtime, runtime
    end

    it 'stays quiet when the asked session is found' do
      refute_includes run_terminal("/exit\n", sessions: cli_sessions(resume: seed_history)), 'No saved session'
    end

    it 'stays quiet when no session was asked for' do
      refute_includes run_terminal("/exit\n"), 'No saved session'
    end

    it 'notifies the missing session below the banner' do
      output = run_terminal("/exit\n", sessions: cli_sessions(resume: 'nope'))

      assert_match(%r{type /help for commands, /exit to quit.*No saved session nope\.}m, output)
    end
  end

  it 'refuses a missing credential with the configuration error' do
    assert_includes run_terminal('', env: {}), 'mock has no api_key'
  end

  it 'returns one when the build is interrupted' do
    sessions = Object.new
    sessions.define_singleton_method(:find) { |_host| raise Interrupt }
    run_terminal('', sessions: sessions)

    assert_equal 1, @status
  end

  it 'shows the model in the banner' do
    assert_includes run_terminal(''), 'mock/test'
  end

  it 'shows the session total in the banner of a resumed session' do
    output = run_terminal("hello\n/resume\n\n") do |runtime|
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
      runtime.agent.provider.stub_response('Hi', token_usage: usage)
    end

    assert_match(/▸ session\s+15 tok$/, output)
  end

  it 'replays nothing of a resumed session on the blocking loop' do
    output = run_terminal("/exit\n", sessions: cli_sessions(resume: seed_history))

    refute_includes output, 'Fixed it.'
  end

  it 'hints at the second Ctrl-C after the first at the prompt' do
    assert_includes run_terminal(interrupting_input(1)), 'Press Ctrl-C again to exit.'
  end

  it 'exits on a second Ctrl-C at the prompt' do
    run_terminal(interrupting_input(2))

    assert_equal 0, @status
  end

  it 'disarms the exit on a line between two Ctrl-Cs' do
    output = run_terminal(scripted_input([:interrupt, "\n", :interrupt]))

    assert_equal 2, output.scan('Press Ctrl-C again to exit.').length
  end

  it 'arms the exit when a Ctrl-C lands in the opening' do
    assert_includes run_terminal("\n", sessions: interrupting_sessions), 'Press Ctrl-C again to exit.'
  end

  it 'arms the exit when a Ctrl-C escapes a turn' do
    output = run_terminal("hello\n\n") do |driven|
      driven.define_singleton_method(:prompt) { |*_args| raise Interrupt }
    end

    assert_includes output, 'Press Ctrl-C again to exit.'
  end

  it 'ends the session at /exit' do
    runtime = nil
    run_terminal("/exit\nhello\n") { |driven| runtime = driven }

    assert_empty runtime.agent.provider.calls
  end

  it 'ends the session at /quit' do
    runtime = nil
    run_terminal("/quit\nhello\n") { |driven| runtime = driven }

    assert_empty runtime.agent.provider.calls
  end

  it 'skips a blank line' do
    runtime = nil
    run_terminal("\n  \n") { |driven| runtime = driven }

    assert_empty runtime.agent.provider.calls
  end

  describe 'the queue loop' do
    def write_asking_command
      FileUtils.mkdir_p(File.join(@home, '.riffer'))
      File.write(File.join(@home, '.riffer', 'rig.rb'), <<~SOURCE)
        Riffer::Rig.extension('greet') do |rig|
          rig.command('who', description: 'Asks') { |ctx| ctx.say("hi, \#{ctx.ask('who?')}") }
        end
      SOURCE
    end

    def seed_unstamped_history
      seed_history.tap { |id| rewrite_session(id) { |lines| lines.map { |line| line.except('recorded_at') } } }
    end

    def notice
      "\r\n  #{Riffer::Rig::Terminal::Replay::NOTICE}\r\n"
    end

    describe 'when Ctrl-C was ignored at launch' do
      before { @inherited = Signal.trap('INT', 'IGNORE') }
      after { Signal.trap('INT', @inherited) }

      it 'dismisses the picker before the first session on Ctrl-C' do
        seed_session('fix the login bug')
        script = lambda do |pty|
          pty.await(Riffer::Rig::Terminal::FramePrompter::HINT)
          pty.type("\u0003")
          pty.await('type /help for commands, /exit to quit')
          pty.type("/exit\r")
        end
        run_on_pty(script, open_picker: true)

        assert_equal 0, @status
      end

      it 'exits on a second Ctrl-C at the prompt' do
        script = lambda do |pty|
          pty.await('type /help for commands, /exit to quit')
          pty.type("\u0003")
          pty.await(Riffer::Rig::Terminal::EXIT_HINT)
          pty.type("\u0003")
        end
        run_on_pty(script)

        assert_equal 0, @status
      end
    end

    it 'arms the exit when a Ctrl-C lands in the opening' do
      script = lambda do |pty|
        pty.await(Riffer::Rig::Terminal::EXIT_HINT)
        pty.type("\u0003")
      end
      run_on_pty(script, sessions: interrupting_sessions)

      assert_equal 0, @status
    end

    it 'opens the picker over the keys before the first session' do
      path = seed_session('fix the login bug')
      script = lambda do |pty|
        pty.await(Riffer::Rig::Terminal::FramePrompter::HINT)
        pty.type("\rtell me more\r/exit\r")
      end
      run_on_pty(script, open_picker: true)

      assert_operator File.readlines(path).length, :>, 3
    end

    it 'asks for a missing credential over the keys' do
      script = lambda do |pty|
        pty.await('api_key')
        pty.type("mock-key\r/exit\r")
      end
      run_on_pty(script, env: {})

      assert_equal 0, @status
    end

    it 'exits on Ctrl-C at a question before the first session' do
      script = lambda do |pty|
        pty.await('api_key')
        pty.type("\u0003")
      end
      run_on_pty(script, env: {})

      assert_equal 1, @status
    end

    it 'restores the terminal when the Runtime cannot be built' do
      script = lambda do |pty|
        pty.await('api_key')
        pty.type("\u0004")
      end

      assert_includes run_on_pty(script, env: {}), Riffer::Rig::Terminal::KeyPipeline::BRACKETED_PASTE_OFF
    end

    it 'fits the banner to the width of the terminal' do
      output = run_on_pty(->(pty) { pty.type("/exit\r") }, columns: 30)

      refute_includes output, Riffer::Rig::Terminal::Banner::WORDMARK.first
    end

    it 'counts the running jobs of the first session in the footer' do
      output = run_on_pty(->(pty) { pty.type("/exit\r") }) do |runtime|
        runtime.define_singleton_method(:running_job_count) { 2 }
      end

      assert_includes output, '2 jobs'
    end

    it 'replays nothing in a fresh session' do
      output = run_on_pty(->(pty) { pty.type("/exit\r") })

      refute_match(/\d steps? · \d\d:\d\d/, output)
    end

    it 'replays the turns of a session resumed at startup, each as its prompt, answer and footer' do
      output = run_on_pty(->(pty) { pty.type("/exit\r") }, resume: seed_history)

      assert_match history, output
    end

    it 'replays them below the banner' do
      output = run_on_pty(->(pty) { pty.type("/exit\r") }, resume: seed_history)

      assert_match(%r{type /help for commands, /exit to quit.*› what is in notes\.txt\?}m, output)
    end

    it 'replays them above the footer' do
      output = run_on_pty(->(pty) { pty.type("/exit\r") }, resume: seed_history)

      assert_includes output, "↑200 · ↓40\r\n\r\n› "
    end

    it 'replays the session picked before the first session' do
      seed_history
      script = lambda do |pty|
        pty.await(Riffer::Rig::Terminal::FramePrompter::HINT)
        pty.type("\r/exit\r")
      end

      assert_match history, run_on_pty(script, open_picker: true)
    end

    it 'shows a notice for a session recorded before its entries were stamped' do
      output = run_on_pty(->(pty) { pty.type("/exit\r") }, resume: seed_unstamped_history)

      assert_includes output, notice
    end

    it 'runs two queued prompts as two turns in order' do
      runtime = nil
      started = Queue.new
      release = Queue.new
      script = lambda do |pty|
        pty.type("one\r")
        started.pop(timeout: TerminalPty::TIMEOUT_SECONDS)
        pty.type("two\r/exit\r")
        pty.await('2 queued')
        2.times { release << true }
      end
      run_on_pty(script) do |driven|
        runtime = driven
        hold_turns(driven, started, release)
      end

      assert_equal(%w[one two], runtime.agent.provider.calls.map { |call| call[:messages].last[:content] })
    end

    describe 'when a background job exits' do
      before do
        @runtimes = []
        @exits = Queue.new
      end

      def run_watching(script, &)
        run_on_pty(script) do |runtime|
          @runtimes << runtime
          runtime.on_job_exit { @exits << true }
          yield runtime if block_given?
        end
      end

      def exit_jobs(count = 1)
        jobs = @runtimes.last.agent.context[:jobs]
        count.times { jobs.register(Process.spawn('true', pgroup: true), 'true', File.open(File::NULL)) }
        count.times { @exits.pop(timeout: TerminalPty::TIMEOUT_SECONDS) || raise('the job never exited') }
      end

      def idle_exit(reply = 'Mock response')
        lambda do |pty|
          pty.await('type /help for commands, /exit to quit')
          exit_jobs
          pty.await(reply)
          pty.type("/exit\r")
        end
      end

      def follow_up_streams(runtime, events, &failure)
        runtime.define_singleton_method(:follow_up) do |&block|
          events.each(&block)
          failure&.call
        end
      end

      def job_exit
        Riffer::Rig::Events::JobExit.new(
          Riffer::Rig::Runtime::JobCompletion.new(
            job_id: 'a1b2c3d4',
            command: 'true',
            exit_status: 0,
            signal: nil,
            duration: 1.0,
            output_path: File::NULL,
            tail: ''
          )
        )
      end

      def reply(text)
        [Riffer::StreamEvents::TextDelta.new(text), Riffer::Rig::Events::TurnEnd.new(:completed, nil)]
      end

      def exits_while_asked(count)
        write_asking_command
        lambda do |pty|
          pty.type("/who\r")
          pty.await('who?')
          exit_jobs(count)
          pty.type("me\r")
          pty.await('Mock response')
          pty.type("/exit\r")
        end
      end

      it 'runs a turn on the exit without a key pressed' do
        run_watching(idle_exit)

        assert_includes @runtimes.last.agent.provider.calls.last[:messages].last[:content], '<background-job '
      end

      it 'shows a notice ahead of that turn' do
        assert_match(/1 background job exited\r\n.*Mock response/m, run_watching(idle_exit))
      end

      it 'keeps a half-typed line through that turn' do
        script = lambda do |pty|
          pty.await('type /help for commands, /exit to quit')
          pty.type('half')
          pty.await('› half')
          exit_jobs
          pty.await('Mock response')
          pty.type(" done\r")
          pty.await('Mock response', count: 2)
          pty.type("/exit\r")
        end
        run_watching(script)

        assert_equal 'half done', @runtimes.last.agent.provider.calls.last[:messages].last[:content]
      end

      it 'holds an exit while a host prompt is open' do
        assert_match(/hi, me.*1 background job exited/m, run_watching(exits_while_asked(1)))
      end

      it 'counts them in its notice' do
        assert_includes run_watching(exits_while_asked(2)), "2 background jobs exited\r\n"
      end

      it 'starts nothing for an exit from a Runtime /new swapped out' do
        held = Queue.new
        release = Queue.new
        checked = Queue.new
        script = lambda do |pty|
          pty.type("/cost\r")
          held.pop(timeout: TerminalPty::TIMEOUT_SECONDS) || raise('the command was never held')
          exit_jobs
          pty.type("/new\r")
          pty.await('1 queued')
          release << true
          checked.pop(timeout: TerminalPty::TIMEOUT_SECONDS) || raise('the exit was never checked')
          pty.type("/exit\r")
        end
        output = run_watching(script) do |runtime|
          if @runtimes.one?
            runtime.define_singleton_method(:run_command) do |*args, &block|
              held << true
              release.pop(timeout: TerminalPty::TIMEOUT_SECONDS)
              super(*args, &block)
            end
          else
            runtime.define_singleton_method(:pending_job_exit_count) { super().tap { checked << true } }
          end
        end

        refute_includes output, 'background job'
      end

      it 'counts the exits that land before its turn takes them' do
        late = 2
        land = method(:exit_jobs)
        output = run_watching(idle_exit) do |runtime|
          runtime.define_singleton_method(:pending_job_exit_count) do
            super().tap do
              land.call(late)
              late = 0
            end
          end
        end

        assert_includes output, "3 background jobs exited\r\n"
      end

      it 'counts the exits its turn takes past an event ahead of the reply' do
        events = [job_exit, Riffer::Rig::Events::Notify.new('Reloaded.', :info), job_exit, *reply('Passed.')]
        output = run_watching(idle_exit('Passed.')) { |runtime| follow_up_streams(runtime, events) }

        assert_includes output, "2 background jobs exited\r\n"
      end

      it 'leaves out of its notice an exit told once the reply has started' do
        events = [job_exit, Riffer::StreamEvents::TextDelta.new('Started.'), job_exit, *reply('Passed.')]
        output = run_watching(idle_exit('Passed.')) { |runtime| follow_up_streams(runtime, events) }

        assert_includes output, "1 background job exited\r\n"
      end

      it 'shows its notice ahead of the report of a turn that ends before its reply' do
        events = [job_exit, Riffer::Rig::Events::TurnEnd.new(:completed, nil)]
        output = run_watching(idle_exit('0 steps')) { |runtime| follow_up_streams(runtime, events) }

        assert_match(/1 background job exited\r\n.*0 steps/m, output)
      end

      it 'shows no notice for a turn that takes no exit' do
        output = run_watching(idle_exit('Passed.')) { |runtime| follow_up_streams(runtime, reply('Passed.')) }

        refute_includes output, 'background job'
      end

      it 'shows its notice ahead of the error that ends its turn' do
        failing = idle_exit('provider down')
        output = run_watching(failing) { |runtime| follow_up_streams(runtime, [job_exit]) { raise 'provider down' } }

        assert_match(/1 background job exited\r\n.*provider down/m, output)
      end
    end

    it 'echoes a submitted line above the footer' do
      output = run_on_pty(->(pty) { pty.type("hello\r/exit\r") })

      assert_includes output, "› hello\r\n\r\n› "
    end

    it 'wraps an echoed line to the terminal width' do
      output = run_on_pty(->(pty) { pty.type("refactor the picker now\r/exit\r") }, columns: 16)

      assert_includes output, "› refactor the\r\n  picker now\r\n"
    end

    it 'asks for a command name on a lone / sent from the palette' do
      script = lambda do |pty|
        pty.await('type /help for commands, /exit to quit')
        pty.type("/\r")
        pty.await(Riffer::Rig::Terminal::COMMAND_HINT)
        pty.type("/exit\r")
      end

      assert_includes run_on_pty(script), Riffer::Rig::Terminal::COMMAND_HINT
    end

    it 'lists the commands the terminal runs itself in the palette' do
      script = lambda do |pty|
        pty.await('type /help for commands, /exit to quit')
        pty.type('/re')
        pty.await('Pick a session to resume')
        pty.type("\u0015/exit\r")
      end

      assert_includes run_on_pty(script), "/resume     Pick a session to resume: /resume --all for every directory's"
    end

    it 'ends the session at /exit' do
      runtime = nil
      run_on_pty(->(pty) { pty.type("/exit\rhello\r") }) { |driven| runtime = driven }

      assert_empty runtime.agent.provider.calls
    end

    it 'ends the session at /quit' do
      runtime = nil
      run_on_pty(->(pty) { pty.type("/quit\rhello\r") }) { |driven| runtime = driven }

      assert_empty runtime.agent.provider.calls
    end

    it 'signs off above the footer when the input ends' do
      assert_includes run_on_pty(->(pty) { pty.type("\u0004") }), "see you on the next riff.\r\n\r\n› "
    end

    it 'exits on a second Ctrl-C at the prompt' do
      script = lambda do |pty|
        # Before the session is up, a Ctrl-C abandons its build instead.
        pty.await('type /help for commands, /exit to quit')
        pty.type("\u0003")
        pty.await(Riffer::Rig::Terminal::EXIT_HINT)
        pty.type("\u0003")
      end
      run_on_pty(script)

      assert_equal 0, @status
    end

    it 'drives the session /new starts' do
      ids = []
      run_on_pty(->(pty) { pty.type("hello\r/new\ragain\r/exit\r") }) { |runtime| ids << runtime.id }
      fresh = session_files.find { |path| File.basename(path, '.jsonl') == ids.last }

      assert_includes File.read(fresh), 'again'
    end

    it 'closes the session /new starts at exit' do
      runtimes = []
      run_on_pty(->(pty) { pty.type("/new\r/exit\r") }) { |runtime| runtimes << runtime }

      assert_raises(Riffer::Rig::Runtime::ClosedError) { runtimes.last.prompt('hello') }
    end

    it 'reads the resume picker over the keys' do
      path = seed_session('fix the login bug')
      script = lambda do |pty|
        pty.type("/resume\r")
        pty.await(Riffer::Rig::Terminal::FramePrompter::HINT)
        pty.type("\r")
        pty.await('▸ model', count: 2)
        pty.type("tell me more\r/exit\r")
      end
      run_on_pty(script)

      assert_operator File.readlines(path).length, :>, 3
    end

    it 'dismisses the resume picker on Ctrl-C' do
      seed_session('fix the login bug')
      runtime = nil
      script = lambda do |pty|
        pty.type("/resume\r")
        pty.await(Riffer::Rig::Terminal::FramePrompter::HINT)
        pty.type('x')
        pty.await('› x')
        cleared = pty.written.scan("› \r\n").size
        pty.type("\u0003")
        # Keys typed before the picker has let go of them would be its own.
        pty.await("› \r\n", count: cleared + 1)
        pty.type("again\r/exit\r")
      end
      run_on_pty(script) { |driven| runtime ||= driven }

      assert_equal 1, runtime.agent.provider.calls.length
    end

    it 'counts the running jobs of the session /new starts in the footer' do
      counts = [0, 3]
      output = run_on_pty(->(pty) { pty.type("/new\r/exit\r") }) do |runtime|
        count = counts.shift
        runtime.define_singleton_method(:running_job_count) { count }
      end

      assert_includes output, '3 jobs'
    end

    it 'replays the session /resume picks below its banner' do
      seed_history
      script = lambda do |pty|
        pty.type("/resume\r")
        pty.await(Riffer::Rig::Terminal::FramePrompter::HINT)
        pty.type("\r")
        pty.await('▸ model', count: 2)
        pty.type("/exit\r")
      end

      assert_match(/(?:▸ model.*){2}#{history}/m, run_on_pty(script))
    end

    it 'replays nothing for the session /new starts' do
      script = lambda do |pty|
        pty.type("/new\r")
        pty.await('▸ model', count: 2)
        pty.type("/exit\r")
      end
      output = run_on_pty(script, resume: seed_history)

      assert_equal 1, output.scan('› also fix the flaky test').size
    end

    it 'cancels the running turn on Ctrl-C' do
      started = Queue.new
      script = lambda do |pty|
        pty.type("hello\r")
        started.pop(timeout: TerminalPty::TIMEOUT_SECONDS)
        pty.type("\u0003")
        pty.await("  interrupted\r\n")
        pty.type("/exit\r")
      end
      output = run_on_pty(script) { |runtime| hold_turns(runtime, started, Queue.new) }

      assert_includes output, "  interrupted\r\n"
    end

    it 'keeps draining the queue after a cancelled turn' do
      runtime = nil
      started = Queue.new
      release = Queue.new
      script = lambda do |pty|
        pty.type("hello\r")
        started.pop(timeout: TerminalPty::TIMEOUT_SECONDS)
        pty.type("again\r/exit\r")
        pty.await('2 queued')
        pty.type("\u0003")
        pty.await("  interrupted\r\n")
        release << true
      end
      run_on_pty(script) do |driven|
        runtime = driven
        hold_turns(driven, started, release)
      end

      assert_includes runtime.agent.provider.calls.last[:messages].last[:content], 'again'
    end

    it 'draws the ticker on the status line while a turn runs' do
      started = Queue.new
      release = Queue.new
      script = lambda do |pty|
        pty.type("hello\r")
        started.pop(timeout: TerminalPty::TIMEOUT_SECONDS)
        pty.await('~$0.0000')
        release << true
        pty.type("/exit\r")
      end
      output = run_on_pty(script) { |runtime| hold_turns(runtime, started, release) }

      assert_includes output, '~$0.0000'
    end

    it 'peeks at the running turn on Ctrl-T' do
      stalled = Queue.new
      release = Queue.new
      script = lambda do |pty|
        pty.type("hello\r")
        stalled.pop(timeout: TerminalPty::TIMEOUT_SECONDS)
        pty.type("\u0014")
        pty.await('  Half a sen')
        release << true
        pty.type("/exit\r")
      end
      output = run_on_pty(script) do |runtime|
        runtime.agent.provider.define_singleton_method(:execute_stream) do |_params, yielder|
          yielder << Riffer::StreamEvents::TextDelta.new('Half a sen')
          stalled << true
          # Stands in for the provider's HTTP read.
          release.pop(timeout: TerminalPty::TIMEOUT_SECONDS)
        end
      end

      assert_includes output, "  Half a sen\r\n› "
    end

    it 'prints the answer and the stat footer above the footer when the turn ends' do
      output = run_on_pty(->(pty) { pty.type("hello\r/exit\r") }) do |runtime|
        runtime.agent.provider.stub_response('Hi from the model')
      end

      assert_match(/\r\n  Hi from the model\.\r\n\r\n  1 step · \d\d:\d\d\r\n\r\n› /, output)
    end

    it 'wraps command output to the width of the terminal' do
      output = run_on_pty(->(pty) { pty.type("/model sonnet\r/exit\r") }, columns: 40)

      assert_includes output, "  Use /model provider/name, with a\r\n  provider from: "
    end

    it 'answers a question asked during a turn from the keys' do
      write_asking_command
      script = lambda do |pty|
        pty.type("/who\r")
        pty.await('who?')
        pty.type("jake\r")
        pty.await('hi, jake')
        pty.type("/exit\r")
      end

      assert_includes run_on_pty(script), 'hi, jake'
    end

    describe 'a question cancelled with Ctrl-C' do
      def cancel_command_question
        write_asking_command
        runtime = nil
        script = lambda do |pty|
          pty.type("/who\r")
          pty.await('who?')
          pty.type('x')
          pty.await('› x')
          cleared = pty.written.scan("› \r\n").size
          pty.type("\u0003")
          # Keys typed before the question has let go of them would be its own.
          pty.await("› \r\n", count: cleared + 1)
          pty.type("jake\r/exit\r")
        end
        output = run_on_pty(script) { |driven| runtime ||= driven }
        [output, runtime]
      end

      def cancel_reload_question
        rig = File.join(@cwd, '.riffer', 'rig.rb')
        script = lambda do |pty|
          pty.type("hello\r")
          pty.await("Trust #{rig}?")
          pty.type("\u0003")
          pty.await("  interrupted\r\n")
          pty.type("/exit\r")
        end
        run_on_pty(script) do |runtime|
          provider = runtime.agent.provider
          provider.stub_response('Reading.', tool_calls: [{ name: 'read', arguments: '{"path":"notes.txt"}' }])
          requests = 0
          provider.define_singleton_method(:stream_text) do |*args, **options, &block|
            requests += 1
            if requests == 1
              # A project rig.rb that appears mid-turn is asked about before the next request.
              FileUtils.mkdir_p(File.dirname(rig))
              File.write(rig, '')
            else
              # Stands in for the provider read the cancel aborts.
              Queue.new.pop(timeout: TerminalPty::TIMEOUT_SECONDS)
            end
            super(*args, **options, &block)
          end
        end
      end

      it 'leaves a command question unanswered' do
        output, = cancel_command_question

        assert_includes output, "hi, \r\n"
      end

      it 'sends the line typed next to the model, not to the question' do
        _, runtime = cancel_command_question

        assert_includes runtime.agent.provider.calls.last[:messages].last[:content], 'jake'
      end

      it 'cancels the turn a reload asked in' do
        output = cancel_reload_question

        assert_includes output, "  interrupted\r\n"
      end
    end
  end

  describe 'a / with no command name' do
    it 'asks for a command name' do
      assert_includes run_terminal("/\n"), 'Type a command name after /'
    end

    it 'sends nothing to the model' do
      runtime = nil
      run_terminal("/\n") { |driven| runtime = driven }

      assert_empty runtime.agent.provider.calls
    end

    it 'sends nothing to the model when text follows it' do
      runtime = nil
      run_terminal("/ hello\n") { |driven| runtime = driven }

      assert_empty runtime.agent.provider.calls
    end
  end

  it 'runs a skill command through run_command' do
    write_skill('tidy')
    output = run_terminal("/skill:tidy\n") { |runtime| runtime.agent.provider.stub_response('Tidied.') }

    assert_includes output, '  Tidied.'
  end

  it 'runs an extension command through run_command' do
    source = <<~RUBY
      Riffer::Rig.extension('greet') do |rig|
        rig.command('hello', description: 'Says hello') { |ctx| ctx.say("hello, \#{ctx.args}") }
      end
    RUBY

    assert_includes run_with_extension("/hello world\n", source), 'hello, world'
  end

  it 'draws no banner on a /model switch' do
    assert_equal 1, run_terminal("/model mock/other\n").scan('▸ model').length
  end

  describe '/new' do
    it 'reports the usage for arguments' do
      output = run_terminal("hello\n/new nope\n")

      assert_includes output, 'Usage: /new'
    end

    it 'keeps driving the current session when the fresh build fails' do
      runtime = nil
      sessions = PreparedSessions.new(cli_sessions) { |driven| runtime = driven }
      started = false
      sessions.define_singleton_method(:fresh) do |host|
        raise Riffer::Rig::Loader::ConfigurationError, 'no fresh' if started

        started = true
        super(host)
      end
      run_terminal("/new\nagain\n", sessions: sessions)

      assert_equal 1, runtime.agent.provider.calls.length
    end

    it 'starts a fresh session with a new id' do
      run_terminal("hello\n/new\nagain\n") { |runtime| runtime.agent.provider.stub_response('Hi') }

      assert_equal 2, session_files.length
    end

    it 'leaves the replaced session intact on disk' do
      run_terminal("hello\n/new\nagain\n") { |runtime| runtime.agent.provider.stub_response('Hi') }
      replaced = session_files.min_by { |path| File.mtime(path) }

      refute_includes File.read(replaced), 'again'
    end

    it 'drives the new session' do
      ids = []
      run_terminal("hello\n/new\nagain\n") do |runtime|
        ids << runtime.id
        runtime.agent.provider.stub_response('Hi')
      end
      fresh = session_files.find { |path| File.basename(path, '.jsonl') == ids.last }

      assert_includes File.read(fresh), 'again'
    end

    it 'closes the new session at exit' do
      runtimes = []
      run_terminal("/new\n/exit\n") { |runtime| runtimes << runtime }

      assert_raises(Riffer::Rig::Runtime::ClosedError) { runtimes.last.prompt('hello') }
    end

    it 'closes the new session when the input fails' do
      runtimes = []
      input = StringIO.new("/new\n")
      input.define_singleton_method(:gets) { super() || raise(IOError, 'input lost') }
      begin
        run_terminal(input) { |runtime| runtimes << runtime }
      rescue IOError
        nil
      end

      assert_raises(Riffer::Rig::Runtime::ClosedError) { runtimes.last.prompt('hello') }
    end
  end

  describe 'the resume picker' do
    it 'reports the usage for other arguments' do
      assert_includes run_terminal("/resume foo\n/exit\n"), 'Usage: /resume [--all]'
    end

    it 'keeps driving the current session when the picker is dismissed' do
      seed_session('fix the login bug')
      seed_session('add picker tests')
      runtime = nil
      run_terminal("/resume\n\nagain\n") { |driven| runtime ||= driven }

      assert_equal 1, runtime.agent.provider.calls.length
    end

    it 'resumes the session the filter narrows to' do
      path = seed_session('fix the login bug')
      seed_session('add picker tests')

      run_terminal("/resume\nlogin\n\ntell me more\n")

      assert_operator File.readlines(path).length, :>, 3
    end

    it 'closes the resumed session at exit' do
      seed_session('fix the login bug')
      runtimes = []
      run_terminal("/resume\nlogin\n\n/exit\n") { |runtime| runtimes << runtime }

      assert_raises(Riffer::Rig::Runtime::ClosedError) { runtimes.last.prompt('hello') }
    end

    it 'keeps the current session when the picked one is missing' do
      seed_session('fix the login bug')
      sessions = cli_sessions
      sessions.define_singleton_method(:resume) { |_host, _id| nil }
      sessions.define_singleton_method(:missing) { |_id = nil| 'wording for the picked one' }

      assert_includes run_terminal("/resume\n\n", sessions: sessions), 'wording for the picked one'
    end

    it 'lists other directories with --all' do
      other = Dir.mktmpdir
      seed_session('fix the login bug')
      seed_session('elsewhere project', cwd: other)

      assert_includes run_terminal("/resume --all\nelsewhere\n\n/exit\n"), 'elsewhere project'
    ensure
      FileUtils.remove_entry(other)
    end

    it 'scopes the picker to the directory without --all' do
      other = Dir.mktmpdir
      seed_session('elsewhere project', cwd: other)

      assert_includes run_terminal("/resume\n/exit\n/exit\n"), 'No saved sessions.'
    ensure
      FileUtils.remove_entry(other)
    end
  end

  describe '/help' do
    it 'reports the usage for arguments' do
      assert_includes run_terminal("/help me\n"), 'Usage: /help'
    end

    it 'lists the commands the terminal runs itself' do
      assert_match %r{/new +Start a fresh session in place}, run_terminal("/help\n")
    end

    it "lists the Runtime's commands" do
      assert_match %r{/trace +Replay the last turn's activity from the session store}, run_terminal("/help\n")
    end

    it 'sends nothing to the model' do
      runtime = nil
      run_terminal("/help\n") { |driven| runtime = driven }

      assert_empty runtime.agent.provider.calls
    end
  end

  it 'reports a turn error and carries on' do
    output = run_terminal("hello\n") do |runtime|
      runtime.agent.provider.define_singleton_method(:stream_text) { |*| raise 'boom' }
    end

    assert_includes output, 'Error: boom'
  end

  it 'reports the response body message of a provider error' do
    error = StandardError.new('status=400')
    error.define_singleton_method(:body) { { error: { message: 'bad model' } } }
    output = run_terminal("hello\n") do |runtime|
      runtime.agent.provider.define_singleton_method(:stream_text) { |*| raise error }
    end

    assert_includes output, 'Error: status=400: bad model'
  end

  it 'cancels the turn on Ctrl-C' do
    output = run_with_interrupter("hello\n")

    assert_includes output, "\n  interrupted\n"
  end

  it 'keeps the session after a cancelled turn' do
    runtime = nil
    run_with_interrupter("hello\nagain\n") { |driven| runtime = driven }

    assert_includes runtime.agent.provider.calls.last[:messages].last[:content], 'hello'
  end

  it 'restores the Ctrl-C handler after a turn' do
    before = Signal.trap('INT', 'DEFAULT')
    Signal.trap('INT', before)
    run_terminal("hello\n") { |runtime| runtime.agent.provider.stub_response('Hi') }
    after = Signal.trap('INT', before)

    assert_equal before, after
  end

  it 'prints only the answer and the stat footer of a turn' do
    output = run_terminal("read it\n") do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: { path: 'missing.txt' } }])
      runtime.agent.provider.stub_response('Done.')
    end

    assert_match(/› \n  Done\. ?\n\n  2 steps · \d\d:\d\d\n\n› /, output)
  end

  it 'prints each turn of a command that prompts twice' do
    source = <<~RUBY
      Riffer::Rig.extension('pair') do |rig|
        rig.command('pair', description: 'Prompts twice') { |ctx| 2.times { ctx.prompt('go') } }
      end
    RUBY
    output = run_with_extension("/pair\n", source) do |runtime|
      runtime.agent.provider.stub_response('First.')
      runtime.agent.provider.stub_response('Second.')
    end

    assert_equal %w[First. Second.], output.scan(/First\.|Second\./)
  end
end
