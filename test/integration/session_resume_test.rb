# frozen_string_literal: true

require 'test_helper'
require 'stringio'

describe 'resuming a saved session in the terminal' do
  before do
    @home = Dir.mktmpdir
    @cwd = Dir.mktmpdir
  end

  after do
    FileUtils.remove_entry(@home)
    FileUtils.remove_entry(@cwd)
  end

  def converse(*argv, prompt:)
    flags = Riffer::Rig::CLI::Flags.parse(['--model', 'mock/test', *argv])
    Riffer::Rig::Terminal.for(
      input: StringIO.new("#{prompt}\n/exit\n"),
      output: StringIO.new,
      version: Riffer::Rig::VERSION,
      sessions: Riffer::Rig::CLI::Sessions.new(
        flags: flags,
        env: Riffer::Rig::Env.load({ 'MOCK_API_KEY' => 'mock-key' }),
        cwd: @cwd,
        home: @home
      )
    ).run
  end

  def session_files
    Dir.glob(File.join(@home, '.riffer', 'sessions', '*', '*.jsonl'))
  end

  def entry_types(path)
    File.readlines(path).map { |line| JSON.parse(line, symbolize_names: true)[:type] }
  end

  it 'keeps one header when -c resumes the session' do
    converse(prompt: 'hello')
    path = session_files.first
    converse('-c', prompt: 'again')

    assert_equal 1, entry_types(path).count('header')
  end

  it 'appends the -c turn to the same session file' do
    converse(prompt: 'hello')
    path = session_files.first
    saved = File.readlines(path).length
    converse('-c', prompt: 'again')

    assert_operator File.readlines(path).length, :>, saved
  end

  it 'keeps one header when -r resumes the session' do
    converse(prompt: 'hello')
    path = session_files.first
    converse('-r', File.basename(path, '.jsonl'), prompt: 'again')

    assert_equal 1, entry_types(path).count('header')
  end
end
