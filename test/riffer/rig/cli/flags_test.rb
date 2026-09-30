# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::CLI::Flags do
  def parse(*argv)
    Riffer::Rig::CLI::Flags.parse(argv)
  end

  it 'keeps everything on by default' do
    flags = parse

    assert_predicate [flags.extensions, flags.skills, flags.agents_md], :all?
  end

  it 'leaves the model to the Loader by default' do
    assert_nil parse.model
  end

  it 'reads --model' do
    assert_equal 'openai/gpt-5', parse('--model', 'openai/gpt-5').model
  end

  it 'reads --no-extensions' do
    refute parse('--no-extensions').extensions
  end

  it 'reads --no-skills' do
    refute parse('--no-skills').skills
  end

  it 'reads --no-agents-md' do
    refute parse('--no-agents-md').agents_md
  end

  it 'reads --tools as identifiers' do
    assert_equal %w[read bash], parse('--tools', 'read,bash').tools
  end

  it 'reads --max-steps as an integer' do
    assert_equal 5, parse('--max-steps', '5').max_steps
  end

  it 'reads --help' do
    assert_predicate parse('--help'), :help
  end

  it 'refuses a non-integer --max-steps' do
    assert_equal 'invalid argument: --max-steps many', parse('--max-steps', 'many')
  end

  it 'refuses an unknown flag' do
    assert_equal 'invalid option: --bogus', parse('--bogus')
  end

  it 'refuses a positional argument' do
    assert_equal 'unexpected argument: hello', parse('hello')
  end

  it 'lists every flag in the usage' do
    usage = Riffer::Rig::CLI::Flags.usage

    assert(
      %w[--model --no-extensions --no-skills --no-agents-md --tools --max-steps].all? do |flag|
        usage.include?(flag)
      end
    )
  end
end
