# frozen_string_literal: true

require 'test_helper'
require 'json'
require 'stringio'

describe Riffer::Rig::Terminal do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
  end

  after do
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def run_terminal(input, env: { 'MOCK_API_KEY' => 'mock-key' }, model: 'mock/test')
    output = StringIO.new
    input = StringIO.new(input) if input.is_a?(String)
    terminal = Riffer::Rig::Terminal.for(input: input, output: output, version: '9.9.9')
    @status = terminal.run do |host|
      @runtime = Riffer::Rig::Loader.runtime(
        cwd: @cwd,
        host: host,
        env: Riffer::Rig::Env.new(env),
        home: @home,
        riffer_config: Riffer::Config.new,
        model: model
      )
      yield @runtime if block_given?
      @runtime
    end
    output.string
  end

  def run_with_extension(input, extension)
    output = StringIO.new
    terminal = Riffer::Rig::Terminal.for(input: StringIO.new(input), output: output, version: '9.9.9')
    @status = terminal.run do |host|
      @runtime = Riffer::Rig::Runtime.new('mock/test', extensions: [extension], host: host, cwd: @cwd)
      yield @runtime if block_given?
      @runtime
    end
    output.string
  end

  def write_skill(name)
    dir = File.join(@cwd, '.agents', 'skills', name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'SKILL.md'), "---\nname: #{name}\ndescription: Skill #{name}.\n---\nDo #{name}.\n")
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

  def interrupt_once
    fired = false
    Riffer::Rig::Extension.new('interrupter') do |rig|
      rig.on(:stream) do
        next if fired

        fired = true
        Process.kill('INT', Process.pid)
        sleep 0.2
      end
    end
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
    run_terminal("/skill:tidy now\n") { |runtime| runtime.agent.provider.stub_response('Tidied.') }

    assert_includes @runtime.agent.provider.calls.last[:messages].last[:content], 'Do tidy.'
  end

  it 'runs an extension command through run_command' do
    extension = Riffer::Rig::Extension.new('greet') do |rig|
      rig.command('hello', description: 'Says hello') { |ctx| ctx.say("hello, #{ctx.args}") }
    end

    assert_includes run_with_extension("/hello world\n", extension), 'hello, world'
  end

  it 'reports an unknown slash command through notify' do
    assert_includes run_terminal("/nope\n"), 'Unknown command: nope'
  end

  it 'ends the session at /exit' do
    run_terminal("/exit\nhello\n")

    assert_empty @runtime.agent.provider.calls
  end

  it 'ends the session at /quit' do
    run_terminal("/quit\nhello\n")

    assert_empty @runtime.agent.provider.calls
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
    output = run_with_extension("hello\n", interrupt_once) do |runtime|
      runtime.agent.provider.stub_response('Hi')
    end

    assert_includes output, '[interrupted: cancelled]'
  end

  it 'keeps the session after a cancelled turn' do
    run_with_extension("hello\nagain\n", interrupt_once) do |runtime|
      runtime.agent.provider.stub_response('Hi')
      runtime.agent.provider.stub_response('Hi again')
    end

    assert_equal 2, @runtime.agent.provider.calls.length
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
end
