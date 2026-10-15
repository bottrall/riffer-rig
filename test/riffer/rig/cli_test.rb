# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe Riffer::Rig::CLI do
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

  def start(*argv, input: "/exit\n", env: { 'MOCK_API_KEY' => 'mock-key' }, output: @output)
    Riffer::Rig::CLI.start(
      argv,
      input: StringIO.new(input),
      output: output,
      error: @error,
      env: Riffer::Rig::Env.load(env),
      cwd: @cwd,
      home: @home
    )
  end

  def tty_output
    Class.new(StringIO) do
      def tty? = true

      def winsize = [24, 80]
    end.new
  end

  def model_env
    { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test' }
  end

  it 'refuses arguments after acp' do
    assert_equal 2, start('acp', '--model', 'mock/test')
  end

  it 'says acp takes no arguments' do
    start('acp', '--model', 'mock/test')

    assert_includes @error.string, 'acp takes no arguments'
  end

  it 'serves ACP on stdio and returns zero when stdin closes' do
    assert_equal 0, start('acp', input: '')
  end

  it 'returns two for an unknown flag' do
    assert_equal 2, start('--bogus')
  end

  it 'names the unknown flag' do
    start('--bogus')

    assert_includes @error.string, 'invalid option: --bogus'
  end

  it 'returns two for a bare -p -r' do
    assert_equal 2, start('-p', '-r', env: model_env)
  end

  it 'prints the usage for --help' do
    start('--help')

    assert_includes @output.string, 'Usage: riffer'
  end

  it 'returns zero for --help' do
    assert_equal 0, start('--help')
  end

  it 'prints the version for --version' do
    start('--version')

    assert_equal "riffer-rig #{Riffer::Rig::VERSION}\n", @output.string
  end

  it 'returns zero for --version' do
    assert_equal 0, start('--version')
  end

  it 'returns two for --verbose without -p' do
    assert_equal 2, start('--verbose')
  end

  it 'says --verbose is headless only' do
    start('--verbose')

    assert_includes @error.string, '--verbose is only available with -p'
  end

  it 'returns two for --json without -p' do
    assert_equal 2, start('--json')
  end

  it 'says --json is headless only' do
    start('--json')

    assert_includes @error.string, '--json is only available with -p'
  end

  it 'returns two for --job-idle-timeout without -p' do
    assert_equal 2, start('--job-idle-timeout', '30')
  end

  it 'says --job-idle-timeout is headless only' do
    start('--job-idle-timeout', '30')

    assert_includes @error.string, '--job-idle-timeout is only available with -p'
  end

  it 'runs one prompt headless and returns zero' do
    assert_equal 0,
                 start(
                   '-p',
                   'hello',
                   input: '',
                   env: { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test' }
                 )
  end

  it 'prints the reply on stdout in headless mode' do
    start('-p', 'hello', input: '', env: { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test' })

    refute_empty @output.string
  end

  it 'allows --verbose with -p' do
    assert_equal 0,
                 start(
                   '-p',
                   '--verbose',
                   'hello',
                   input: '',
                   env: { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test' }
                 )
  end

  it 'allows --job-idle-timeout with -p' do
    assert_equal 0, start('-p', '--job-idle-timeout', '30', 'hello', input: '', env: model_env)
  end

  it 'prints JSON events for --json with -p' do
    start('-p', '--json', 'hello', input: '', env: { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test' })

    assert_includes @output.string, '"type":"session_start"'
  end

  describe 'session flags' do
    def session_files
      Dir.glob(File.join(@home, '.riffer', 'sessions', '*', '*.jsonl'))
    end

    it 'returns two when -p -c has no saved session' do
      assert_equal 2, start('-p', '-c', 'again', input: '', env: model_env)
    end

    it 'says there is no saved session when -p -c has none' do
      start('-p', '-c', 'again', input: '', env: model_env)

      assert_includes @error.string, 'No saved session in this directory.'
    end

    it 'returns two for -p -r with an unknown id' do
      assert_equal 2, start('-p', '-r', 'nope', 'again', input: '', env: model_env)
    end

    it 'says the session is missing for -p -r with an unknown id' do
      start('-p', '-r', 'nope', 'again', input: '', env: model_env)

      assert_includes @error.string, 'No saved session nope.'
    end

    it 'keeps one header when -p -c continues the session' do
      start('-p', 'hello', input: '', env: model_env)
      path = session_files.first
      start('-p', '-c', 'again', input: '', env: model_env)
      types = File.readlines(path).map { |line| JSON.parse(line, symbolize_names: true)[:type] }

      assert_equal 1, types.count('header')
    end

    it 'appends the -p -c turn to the same session file' do
      start('-p', 'hello', input: '', env: model_env)
      path = session_files.first
      saved = File.readlines(path).length

      start('-p', '-c', 'again', input: '', env: model_env)

      assert_operator File.readlines(path).length, :>, saved
    end

    it 'keeps one header when -p -r resumes the session' do
      start('-p', 'hello', input: '', env: model_env)
      path = session_files.first
      id = File.basename(path, '.jsonl')

      start('-p', '-r', id, 'again', input: '', env: model_env)
      types = File.readlines(path).map { |line| JSON.parse(line, symbolize_names: true)[:type] }

      assert_equal 1, types.count('header')
    end
  end

  it 'runs the terminal with no arguments and returns zero' do
    assert_equal 0, start(env: { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test' })
  end

  it 'returns one for a bare RIFFER_MODEL' do
    assert_equal 1, start(env: { 'RIFFER_MODEL' => 'sonnet' })
  end

  it 'colours a terminal' do
    output = tty_output
    start(env: { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test' }, output: output)

    assert_includes output.string, "\e[38"
  end

  it 'drops the colour under NO_COLOR' do
    output = tty_output
    start(env: { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test', 'NO_COLOR' => '1' }, output: output)

    refute_includes output.string, "\e["
  end

  it 'opens the picker for a bare -r' do
    assert_equal 0, start('-r', env: model_env)
  end

  it 'shows the picker for a bare -r' do
    start('-r', env: model_env)

    assert_includes @output.string, 'No saved sessions.'
  end
end
