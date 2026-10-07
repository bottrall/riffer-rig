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

  def start(*argv, input: "/exit\n", env: { 'MOCK_API_KEY' => 'mock-key' })
    Riffer::Rig::CLI.start(
      argv,
      input: StringIO.new(input),
      output: @output,
      error: @error,
      env: Riffer::Rig::Env.load(env),
      cwd: @cwd,
      home: @home
    )
  end

  def write_skill(name)
    dir = File.join(@cwd, '.agents', 'skills', name)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'SKILL.md'), "---\nname: #{name}\ndescription: Skill #{name}.\n---\nDo #{name}.\n")
  end

  it 'runs the terminal with no arguments and returns zero' do
    assert_equal 0, start(env: { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test' })
  end

  it 'hands --model to the Loader' do
    start('--model', 'mock/flagged')

    assert_includes @output.string, 'mock/flagged'
  end

  it 'hands --no-skills to the Loader' do
    write_skill('tidy')
    start('--model', 'mock/test', '--no-skills')

    assert_match(/skills\s+none/, @output.string)
  end

  it 'returns one for a bare RIFFER_MODEL' do
    assert_equal 1, start(env: { 'RIFFER_MODEL' => 'sonnet' })
  end

  it 'prints the usage for --help' do
    start('--help')

    assert_includes @output.string, 'Usage: riffer'
  end

  it 'returns zero for --help' do
    assert_equal 0, start('--help')
  end

  it 'returns two for an unknown flag' do
    assert_equal 2, start('--bogus')
  end

  it 'names the unknown flag' do
    start('--bogus')

    assert_includes @error.string, 'invalid option: --bogus'
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

  it 'returns two when -p has no prompt' do
    assert_equal 2, start('-p', input: '', env: { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test' })
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

  it 'serves ACP on stdio and returns zero when stdin closes' do
    assert_equal 0, start('acp', input: '')
  end

  it 'refuses arguments after acp' do
    assert_equal 2, start('acp', '--model', 'mock/test')
  end

  describe 'session flags' do
    def model_env
      { 'MOCK_API_KEY' => 'mock-key', 'RIFFER_MODEL' => 'mock/test' }
    end

    def session_files
      Dir.glob(File.join(@home, '.riffer', 'sessions', '*', '*.jsonl'))
    end

    it 'starts fresh when -c has no saved session' do
      assert_equal 0, start('-c', env: model_env)
    end

    it 'notifies when -c has no saved session' do
      start('-c', env: model_env)

      assert_includes @output.string, 'No saved session in this directory.'
    end

    it 'keeps one header when -c resumes the session' do
      start(input: "hello\n/exit\n", env: model_env)
      path = session_files.first
      start('-c', input: "again\n/exit\n", env: model_env)
      types = File.readlines(path).map { |line| JSON.parse(line, symbolize_names: true)[:type] }

      assert_equal 1, types.count('header')
    end

    it 'appends the -c turn to the same session file' do
      start(input: "hello\n/exit\n", env: model_env)
      path = session_files.first
      saved = File.readlines(path).length

      start('-c', input: "again\n/exit\n", env: model_env)

      assert_operator File.readlines(path).length, :>, saved
    end

    it 'keeps one header when -r resumes the session' do
      start(input: "hello\n/exit\n", env: model_env)
      path = session_files.first
      id = File.basename(path, '.jsonl')

      start('-r', id, input: "again\n/exit\n", env: model_env)
      types = File.readlines(path).map { |line| JSON.parse(line, symbolize_names: true)[:type] }

      assert_equal 1, types.count('header')
    end

    it 'starts fresh for an unknown -r id' do
      assert_equal 0, start('-r', 'nope', env: model_env)
    end

    it 'notifies for an unknown -r id' do
      start('-r', 'nope', env: model_env)

      assert_includes @output.string, 'No saved session nope.'
    end

    it 'opens the picker for a bare -r' do
      assert_equal 0, start('-r', env: model_env)
    end

    it 'shows the picker for a bare -r' do
      start('-r', env: model_env)

      assert_includes @output.string, 'No saved sessions.'
    end

    describe 'headless' do
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

      it 'keeps one header when -p -r resumes the session' do
        start('-p', 'hello', input: '', env: model_env)
        path = session_files.first
        id = File.basename(path, '.jsonl')

        start('-p', '-r', id, 'again', input: '', env: model_env)
        types = File.readlines(path).map { |line| JSON.parse(line, symbolize_names: true)[:type] }

        assert_equal 1, types.count('header')
      end

      it 'returns two for a bare -p -r' do
        assert_equal 2, start('-p', '-r', env: model_env)
      end
    end
  end
end
