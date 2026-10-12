# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'stringio'

# Delegates to the real sessions collaborator and hands each built Runtime to
# the block, so tests can stub the provider before the REPL reads a prompt.
class PreparedSessions
  def initialize(sessions, &prepare)
    @sessions = sessions
    @prepare = prepare
  end

  def start(host)
    prepare(@sessions.start(host))
  end

  def fresh(host)
    prepare(@sessions.fresh(host))
  end

  def resume(host, id)
    prepare(@sessions.resume(host, id))
  end

  def list(host, all: false)
    @sessions.list(host, all: all)
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

class RecordingAnimator
  attr_reader :calls

  def initialize
    @calls = []
  end

  def reveal(_frames) = nil

  def start(mode = :neutral)
    @calls << mode
  end

  def stop
    @calls << :stop
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

  def cli_sessions(env: { 'MOCK_API_KEY' => 'mock-key' })
    Riffer::Rig::CLI::Sessions.new(
      flags: Riffer::Rig::CLI::Flags.new(model: 'mock/test'),
      env: Riffer::Rig::Env.new(env),
      cwd: @cwd,
      home: @home
    )
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

  def run_with_animator(input, animator, &)
    output = StringIO.new
    input = StringIO.new(input)
    sessions = PreparedSessions.new(cli_sessions, &)
    theme = Riffer::Rig::Terminal::Theme.for(output, no_color: true)
    renderer = Riffer::Rig::Terminal::Renderer.new(
      io: output,
      theme: theme,
      smoother: Riffer::Rig::Terminal::Smoother.new(io: output, theme: theme),
      cursor: Riffer::Rig::Terminal::Cursor.new(io: output, theme: theme)
    )
    host = Riffer::Rig::Terminal::Host.new(input: input, renderer: renderer, animator: animator)
    Riffer::Rig::Terminal.new(
      input: input,
      host: host,
      renderer: renderer,
      animator: animator,
      theme: theme,
      version: '9.9.9',
      sessions: sessions,
      picker: Riffer::Rig::Terminal::Picker.new(input: input, renderer: renderer, host: host, sessions: sessions)
    ).run
  end

  def run_with_extension(input, source, &)
    dir = File.join(@home, '.riffer')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'rig.rb'), source)
    run_terminal(input, &)
  end

  def run_with_interrupter(input)
    run_terminal(input) do |runtime|
      cancelled = Queue.new
      runtime.define_singleton_method(:cancel) do
        super()
        cancelled << true
      end
      fired = false
      runtime.agent.provider.define_singleton_method(:stream_text) do |*args, **options, &block|
        unless fired
          fired = true
          Process.kill('INT', Process.pid)
          # The trap hands the cancel to a thread, which has to land before
          # the turn reaches the message boundary that honours it.
          cancelled.pop(timeout: 5)
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

  def seed_session(title, cwd: @cwd, updated: Time.now)
    runtime = Riffer::Rig::Loader.runtime(
      cwd: cwd,
      host: Riffer::Rig::Hosts::Null.new,
      env: Riffer::Rig::Env.new('MOCK_API_KEY' => 'mock-key'),
      home: @home,
      riffer_config: Riffer::Config.new,
      options: Riffer::Rig::Loader::Options.new(model: 'mock/test'),
      store: Riffer::Rig::Stores::JSONL.new(home: @home)
    )
    runtime.prompt(title) { |event| event } # the turn only runs when its events are consumed
    runtime.close
    path = session_file_for(title, cwd: cwd)
    File.utime(updated, updated, path)
    path
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
    input = Object.new
    input.define_singleton_method(:gets) do
      remaining -= 1
      raise Interrupt unless remaining.negative?
    end
    input
  end

  def scripted_input(steps)
    remaining = steps.dup
    input = Object.new
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

  describe 'bare -r' do
    it 'opens the picker before the first session' do
      path = seed_session('fix the login bug')

      run_terminal("\nhello\n", open_picker: true)

      assert_operator File.readlines(path).length, :>, 3
    end

    it 'starts fresh when the picker is dismissed' do
      assert_includes run_terminal("/exit\n", open_picker: true), 'No saved sessions.'
    end

    it 'takes the missing-session wording from the sessions collaborator' do
      sessions = Object.new
      sessions.define_singleton_method(:start) { |_host| nil }
      sessions.define_singleton_method(:resume) { |_host, _id| nil }
      sessions.define_singleton_method(:list) do |_host, **|
        [Riffer::Rig::Terminal::Session.new(id: 'nope', title: 'gone', updated: Time.now, cwd: Dir.pwd)]
      end
      sessions.define_singleton_method(:missing) { |id| "wording for #{id}" }

      assert_includes run_terminal("\n", open_picker: true, sessions: sessions), 'wording for nope'
    end
  end

  it 'refuses a missing credential with the configuration error' do
    assert_includes run_terminal('', env: {}), 'mock has no api_key'
  end

  it 'returns one when the build is interrupted' do
    sessions = Object.new
    sessions.define_singleton_method(:start) { |_host| raise Interrupt }
    run_terminal('', sessions: sessions)

    assert_equal 1, @status
  end

  it 'shows the model in the banner' do
    assert_includes run_terminal(''), 'mock/test'
  end

  it 'counts the skills in the banner' do
    write_skill('tidy')

    assert_match(/skills\s+1/, run_terminal(''))
  end

  it 'shows none in the banner without skills' do
    assert_match(/skills\s+none/, run_terminal(''))
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

  it 'runs a skill command through run_command' do
    write_skill('tidy')
    output = run_terminal("/skill:tidy\n") { |runtime| runtime.agent.provider.stub_response('Tidied.') }

    assert_includes output, '✦ skill: tidy'
  end

  it 'runs an extension command through run_command' do
    source = <<~RUBY
      Riffer::Rig.extension('greet') do |rig|
        rig.command('hello', description: 'Says hello') { |ctx| ctx.say("hello, \#{ctx.args}") }
      end
    RUBY

    assert_includes run_with_extension("/hello world\n", source), 'hello, world'
  end

  describe 'a /model switch' do
    def switch(input)
      run_terminal(input) do |runtime|
        usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
        runtime.agent.provider.stub_response('Hi', token_usage: usage)
      end
    end

    it 're-renders the banner with the new model' do
      assert_match(%r{▸ model\s+mock/other}, switch("/model mock/other\n"))
    end

    it 'shows the session total in the re-rendered banner' do
      assert_match(/▸ session\s+15 tok$/, switch("hello\n/model mock/other\n"))
    end

    it 'leaves the banner alone when the model is unchanged' do
      assert_equal 1, switch("/model\n").scan('▸ model').length
    end
  end

  describe '/new' do
    it 'reports the usage for arguments' do
      output = run_terminal("hello\n/new nope\n")

      assert_includes output, 'Usage: /new'
    end

    it 'keeps driving the current session when the fresh build fails' do
      runtime = nil
      sessions = PreparedSessions.new(cli_sessions) { |driven| runtime = driven }
      sessions.define_singleton_method(:fresh) { |_host| raise Riffer::Rig::Loader::ConfigurationError, 'no fresh' }
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

  it 'reports a turn error and carries on' do
    output = run_terminal("hello\n") do |runtime|
      runtime.agent.provider.define_singleton_method(:stream_text) { |*| raise 'boom' }
    end

    assert_includes output, 'Error: boom'
  end

  it 'cancels the turn on Ctrl-C' do
    output = run_with_interrupter("hello\n")

    assert_includes output, '[interrupted: cancelled]'
  end

  it 'keeps the session after a cancelled turn' do
    runtime = nil
    run_with_interrupter("hello\nagain\n") { |driven| runtime = driven }

    assert_equal 2, runtime.agent.provider.calls.length
  end

  it 'restores the Ctrl-C handler after a turn' do
    before = Signal.trap('INT', 'DEFAULT')
    Signal.trap('INT', before)
    run_terminal("hello\n") { |runtime| runtime.agent.provider.stub_response('Hi') }
    after = Signal.trap('INT', before)

    assert_equal before, after
  end

  it 'switches the animator to reasoning while the model reasons' do
    animator = RecordingAnimator.new
    run_with_animator("hello\n", animator) do |runtime|
      runtime.agent.provider.stub_response('Hi', reasoning: [{ type: :text, text: 'thinking' }])
    end

    assert_includes animator.calls, :reasoning
  end

  it 'returns the animator to neutral when the reasoning is done' do
    animator = RecordingAnimator.new
    run_with_animator("hello\n", animator) do |runtime|
      runtime.agent.provider.stub_response('Hi', reasoning: [{ type: :text, text: 'thinking' }])
    end

    assert_includes animator.calls.each_cons(2), %i[reasoning neutral]
  end

  it 'renders streamed text' do
    output = run_terminal("hello\n") { |runtime| runtime.agent.provider.stub_response('Hi from the model') }

    assert_includes output, 'Hi from the model'
  end

  it 'renders a tool call' do
    output = run_terminal("read it\n") do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: { path: 'missing.txt' } }])
      runtime.agent.provider.stub_response('Done.')
    end

    assert_includes output, '⚙ read(path: "missing.txt")'
  end

  it 'renders nothing for the before_tool_call and after_tool_call events' do
    output = run_terminal("read it\n") do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: { path: 'missing.txt' } }])
      runtime.agent.provider.stub_response('Done.')
    end

    refute_match(/(before|after)_tool_call|Events::/, output)
  end

  it 'renders the cost line from turn_end' do
    output = run_terminal("hello\n") do |runtime|
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
      runtime.agent.provider.stub_response('Hi', token_usage: usage)
    end

    assert_includes output, '↑10 · ↓5 · session 15 tok'
  end

  it 'leaves the animator alone for a message that is not a tool result' do
    animator = RecordingAnimator.new
    run_with_animator("hello\n", animator) { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal [:neutral], animator.calls - [:stop]
  end

  it 'renders a tool result once' do
    File.write(File.join(@cwd, 'note.txt'), 'the note')
    output = run_terminal("read it\n") do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: { path: 'note.txt' } }])
      runtime.agent.provider.stub_response('Done.')
    end

    assert_equal 1, output.scan('↳ ').size
  end

  it 'renders a tool result under its call' do
    File.write(File.join(@cwd, 'note.txt'), 'the note')
    output = run_terminal("read it\n") do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: { path: 'note.txt' } }])
      runtime.agent.provider.stub_response('Done.')
    end

    assert_includes output, '↳ '
  end
end
