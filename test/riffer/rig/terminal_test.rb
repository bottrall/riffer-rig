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

describe Riffer::Rig::Terminal do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
  end

  after do
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def run_terminal(
    input,
    env: { 'MOCK_API_KEY' => 'mock-key' },
    model: 'mock/test',
    open_picker: false,
    sessions: nil,
    &
  )
    output = StringIO.new
    input = StringIO.new(input) if input.is_a?(String)
    sessions ||= Riffer::Rig::CLI::Sessions.new(
      flags: Riffer::Rig::CLI::Flags.new(model: model),
      env: Riffer::Rig::Env.new(env),
      cwd: @cwd,
      home: @home
    )
    sessions = PreparedSessions.new(sessions, &) if block_given?
    terminal = Riffer::Rig::Terminal.for(input: input, output: output, version: '9.9.9', sessions: sessions)
    @status = terminal.run(open_picker: open_picker)
    output.string
  end

  def run_with_extension(input, source, &)
    dir = File.join(@home, '.riffer')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'rig.rb'), source)
    run_terminal(input, &)
  end

  def run_with_interrupter(input, &)
    run_with_extension(input, <<~RUBY, &)
      Riffer::Rig.extension('interrupter') do |rig|
        fired = false
        rig.on(:stream) do
          next if fired
          fired = true
          Process.kill('INT', Process.pid)
          sleep 0.2
        end
      end
    RUBY
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
      model: 'mock/test',
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

  def session_file_for(title, cwd: nil)
    files = cwd ? session_files.select { |path| header_of(path)[:cwd] == cwd } : session_files
    files.find { |path| header_of(path)[:title] == title }
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

  it 'references no Riffer::Rig constant outside the public host API' do
    sources = [File.expand_path('../../../lib/riffer/rig/terminal.rb', __dir__),
               *Dir[File.expand_path('../../../lib/riffer/rig/terminal/**/*.rb', __dir__)]]
    referenced = sources.flat_map { |path| File.read(path).scan(/Riffer::Rig::(\w+)/).flatten }.uniq

    assert_empty referenced - %w[Terminal Runtime Hosts Loader Events Command Turn]
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

  it 'renders a tool result under its call' do
    File.write(File.join(@cwd, 'note.txt'), 'the note')
    output = run_terminal("read it\n") do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: { path: 'note.txt' } }])
      runtime.agent.provider.stub_response('Done.')
    end

    assert_includes output, '↳ '
  end

  it 'renders the cost line from turn_end' do
    output = run_terminal("hello\n") do |runtime|
      usage = Riffer::Providers::TokenUsage.new(input_tokens: 10, output_tokens: 5)
      runtime.agent.provider.stub_response('Hi', token_usage: usage)
    end

    assert_includes output, '↑10 · ↓5 · session 15 tok'
  end

  it 'shows the model in the banner' do
    assert_includes run_terminal(''), 'mock/test'
  end

  it 'counts the skills in the banner' do
    write_skill('tidy')

    assert_match(/skills\s+1/, run_terminal(''))
  end

  it 'runs a skill command through run_command' do
    write_skill('tidy')
    output = run_terminal("/skill:tidy\n") { |runtime| runtime.agent.provider.stub_response('Tidied.') }

    assert_includes output, '✦ skill: tidy'
  end

  it 'sends the skill body as a user turn' do
    write_skill('tidy')
    runtime = nil
    run_terminal("/skill:tidy now\n") do |driven|
      runtime = driven
      driven.agent.provider.stub_response('Tidied.')
    end

    assert_includes runtime.agent.provider.calls.last[:messages].last[:content], 'Do tidy.'
  end

  it 'runs an extension command through run_command' do
    source = <<~RUBY
      Riffer::Rig.extension('greet') do |rig|
        rig.command('hello', description: 'Says hello') { |ctx| ctx.say("hello, \#{ctx.args}") }
      end
    RUBY

    assert_includes run_with_extension("/hello world\n", source), 'hello, world'
  end

  it 'reports an unknown slash command through notify' do
    assert_includes run_terminal("/nope\n"), 'Unknown command: nope'
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

  it 'returns zero when the session ends' do
    run_terminal("/exit\n")

    assert_equal 0, @status
  end

  it 'signs off when the input ends' do
    assert_match(/see you on the next riff\.\n\z/, run_terminal(''))
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

  it 'hints at the second Ctrl-C after the first at the prompt' do
    assert_includes run_terminal(interrupting_input(1)), 'Press Ctrl-C again to exit.'
  end

  it 'exits on a second Ctrl-C at the prompt' do
    run_terminal(interrupting_input(2))

    assert_equal 0, @status
  end

  it 'refuses a missing credential with the configuration error' do
    assert_includes run_terminal('', env: {}), 'mock has no api_key'
  end

  it 'returns one when the Runtime cannot be built' do
    run_terminal('', env: {})

    assert_equal 1, @status
  end

  it 'writes the onboarded model to home settings' do
    run_terminal("mock/test\nmock-key\n/exit\n", env: {}, model: nil)

    assert_equal 'mock/test', JSON.parse(File.read(File.join(@home, '.riffer', 'settings.json')))['model']
  end

  it 'writes the pasted key to home auth.json' do
    run_terminal("mock/test\nmock-key\n/exit\n", env: {}, model: nil)

    assert_equal 'mock-key', JSON.parse(File.read(File.join(@home, '.riffer', 'auth.json')))['mock']['api_key']
  end

  describe '/new' do
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

    it 'keeps driving the current session when the fresh build fails' do
      output = run_terminal("hello\n/new nope\n")

      assert_includes output, 'Usage: /new'
    end
  end

  describe 'the resume picker' do
    it 'lists the sessions of the directory' do
      seed_session('fix the login bug')
      seed_session('add picker tests')

      assert_includes run_terminal("/resume\n/exit\n/exit\n"), 'add picker tests'
    end

    it 'filters the rows by typed text' do
      seed_session('fix the login bug')
      seed_session('add picker tests')

      output = run_terminal("/resume\nlogin\n/exit\n/exit\n")

      assert_equal 2, output.scan('fix the login bug').length
    end

    it 'resumes the session the filter narrows to' do
      path = seed_session('fix the login bug')
      seed_session('add picker tests')

      run_terminal("/resume\nlogin\n\ntell me more\n")

      assert_operator File.readlines(path).length, :>, 3
    end

    it 'switches to a numbered row' do
      path = seed_session('fix the login bug', updated: Time.now - 3600)
      seed_session('add picker tests')

      run_terminal("/resume\n2\ntell me more\n")

      assert_operator File.readlines(path).length, :>, 3
    end

    it 'shows the relative time on a row' do
      seed_session('fix the login bug')

      assert_match(/fix the login bug — just now/, run_terminal("/resume\n/exit\n/exit\n"))
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

    it 'deletes a session after Ctrl-D and confirm' do
      seed_session('fix the login bug', updated: Time.now - 3600)
      seed_session('add picker tests')

      run_terminal("/resume\n\x04\n1\ny\n")

      assert_nil session_file_for('add picker tests')
    end

    it 'keeps the unconfirmed session' do
      seed_session('fix the login bug', updated: Time.now - 3600)
      seed_session('add picker tests')

      run_terminal("/resume\n\x04\n1\nn\n")

      assert_equal 2, session_files.length
    end

    it 'reports the usage for other arguments' do
      assert_includes run_terminal("/resume foo\n/exit\n"), 'Usage: /resume [--all]'
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
  end
end
