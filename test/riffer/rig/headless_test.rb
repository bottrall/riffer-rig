# frozen_string_literal: true

require 'test_helper'
require 'stringio'

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
    max_steps: nil,
    &block
  )
    input = StringIO.new(input) if input.is_a?(String)
    @status = Riffer::Rig::Headless.for(input: input, output: @output, error: @error, verbose: verbose).run(
      prompt: prompt
    ) do |host|
      @runtime = Riffer::Rig::Loader.runtime(
        cwd: @cwd,
        host: host,
        env: Riffer::Rig::Env.new(env),
        home: @home,
        riffer_config: Riffer::Config.new,
        model: model,
        max_steps: max_steps
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

  def with_sdk_absent_and_installable
    gem_specs = Gem::Specification.method(:find_by_name)
    bundler = Riffer::Rig::SDK.method(:bundler?)
    Gem::Specification.define_singleton_method(:find_by_name) { |*_args| raise Gem::LoadError, 'not installed' }
    Riffer::Rig::SDK.define_singleton_method(:bundler?) { false }
    yield
  ensure
    Gem::Specification.define_singleton_method(:find_by_name, gem_specs)
    Riffer::Rig::SDK.define_singleton_method(:bundler?, bundler)
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

  def prompt_sent_to_model
    @runtime.agent.provider.calls.first[:messages].last[:content]
  end

  it 'prints only the streamed reply on stdout' do
    run_headless(prompt: 'hello') { |runtime| runtime.agent.provider.stub_response('Hi from the model') }

    assert_includes @output.string, 'Hi from the model'
  end

  it 'ends the output with a newline' do
    run_headless(prompt: 'hello') { |runtime| runtime.agent.provider.stub_response('Hi from the model') }

    assert_match(/\n\z/, @output.string)
  end

  it 'returns zero for a completed turn' do
    run_headless(prompt: 'hello') { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal 0, @status
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

  it 'returns two for a bare model name' do
    run_headless(prompt: 'hello', model: nil, env: { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'sonnet' })

    assert_equal 2, @status
  end

  it 'names the model string shape for a bare model name' do
    run_headless(prompt: 'hello', model: nil, env: { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'sonnet' })

    assert_match(%r{not a provider/name model string}, @error.string)
  end

  it 'returns two for a declined optional SDK install' do
    with_sdk_absent_and_installable do
      run_headless(prompt: 'hello', model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk' })
    end

    assert_equal 2, @status
  end

  it 'prints the install line for a declined optional SDK install' do
    with_sdk_absent_and_installable do
      run_headless(prompt: 'hello', model: 'openai/o3', env: { 'OPENAI_API_KEY' => 'sk' })
    end

    assert_match(/gem install openai/, @error.string)
  end

  it 'returns three when the turn hits max_steps' do
    run_headless(prompt: 'go', max_steps: 1) do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('second response')
    end

    assert_equal 3, @status
  end

  it 'says the turn ended with the stop reason when it did not complete' do
    run_headless(prompt: 'go', max_steps: 1) do |runtime|
      runtime.agent.provider.stub_response('', tool_calls: [{ name: 'read', arguments: '{"path":"/tmp/x"}' }])
      runtime.agent.provider.stub_response('second response')
    end

    assert_match(/turn ended: max_steps/, @error.string)
  end

  it 'returns one for a provider stop reason that is not completion' do
    run_headless(prompt: 'hello') { |runtime| runtime.agent.provider.stub_response('nope', finish_reason: :error) }

    assert_equal 1, @status
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

  it 'returns 130 when interrupted and the turn is cancelled' do
    run_with_extension(interrupt_once) { |runtime| runtime.agent.provider.stub_response('Hi') }

    assert_equal 130, @status
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
end
