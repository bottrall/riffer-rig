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

  it 'stubs riffer -p until headless lands' do
    assert_equal 2, start('-p', 'hello')
  end

  it 'says riffer -p is not available yet' do
    start('-p', 'hello')

    assert_includes @error.string, 'riffer -p is not available yet'
  end

  it 'stubs riffer acp until ACP lands' do
    assert_equal 2, start('acp')
  end
end
