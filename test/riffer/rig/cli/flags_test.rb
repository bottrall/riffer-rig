# frozen_string_literal: true

require 'test_helper'

describe Riffer::Rig::CLI::Flags do
  def parse(*argv)
    Riffer::Rig::CLI::Flags.parse(argv)
  end

  describe '.parse' do
    it 'refuses a positional argument' do
      assert_equal 'unexpected argument: hello', parse('hello')
    end

    it 'refuses a second positional with -p' do
      assert_equal 'unexpected argument: hello extra', Riffer::Rig::CLI::Flags.parse(%w[-p hello extra], prompt: true)
    end

    it 'refuses a bare -r with -p' do
      assert_equal 'missing argument: -r', Riffer::Rig::CLI::Flags.parse(%w[-p -r], prompt: true)
    end

    it 'refuses a bare -r followed by a flag with -p' do
      assert_equal 'missing argument: -r', Riffer::Rig::CLI::Flags.parse(%w[-r -p hello], prompt: true)
    end

    it 'refuses any other flag missing its argument' do
      assert_equal 'missing argument: --model', parse('--model')
    end

    it 'refuses a non-integer --max-steps' do
      assert_equal 'invalid argument: --max-steps many', parse('--max-steps', 'many')
    end

    it 'refuses an unknown flag' do
      assert_equal 'invalid option: --bogus', parse('--bogus')
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

    it 'saves the session by default' do
      assert parse.save
    end

    it 'reads --no-save' do
      refute parse('--no-save').save
    end

    it 'reads --verbose' do
      assert parse('--verbose').verbose
    end

    it 'keeps --verbose off by default' do
      refute parse.verbose
    end

    it 'takes the prompt positional with -p' do
      assert_equal 'hello', Riffer::Rig::CLI::Flags.parse(%w[-p hello], prompt: true).prompt
    end

    it 'leaves the prompt to stdin without an argument' do
      assert_nil Riffer::Rig::CLI::Flags.parse(['-p'], prompt: true).prompt
    end

    it 'reads --resume with an id' do
      assert_equal 'abc', parse('--resume', 'abc').resume
    end

    it 'reads -r with an id' do
      assert_equal 'abc', parse('-r', 'abc').resume
    end

    it 'reads --resume=ID' do
      assert_equal 'abc', parse('--resume=abc').resume
    end

    it 'reads -r with an id under -p' do
      assert_equal 'abc', Riffer::Rig::CLI::Flags.parse(%w[-p -r abc], prompt: true).resume
    end

    it 'opens the picker for a bare -r' do
      assert_equal '', parse('-r').resume
    end

    it 'opens the picker for a bare --resume' do
      assert_equal '', parse('--resume').resume
    end

    it 'keeps the flags parsed before a bare -r' do
      refute parse('--no-save', '-r').save
    end

    it 'opens the picker for a bare -r followed by a flag' do
      assert_equal '', parse('-r', '--no-save').resume
    end

    it 'opens the picker for a bare --resume followed by a flag' do
      assert_equal '', parse('--resume', '--no-save').resume
    end

    it 'reads the flag after a bare -r' do
      refute parse('-r', '--no-save').save
    end

    it 'reads --help' do
      assert_predicate parse('--help'), :help
    end
  end

  describe '.usage' do
    it 'lists every flag in the usage' do
      usage = Riffer::Rig::CLI::Flags.usage

      assert(
        %w[--model --no-extensions --no-skills --no-agents-md --tools --max-steps -p --verbose].all? do |flag|
          usage.include?(flag)
        end
      )
    end
  end

  describe '#to_options' do
    it 'builds the Loader options from the flags' do
      options = parse('--model', 'openai/gpt-5', '--no-skills', '--tools', 'read,bash', '--max-steps', '5').to_options

      assert_equal ['openai/gpt-5', false, %w[read bash], 5],
                   [options.model, options.skills, options.tools, options.max_steps]
    end

    it 'keeps the Loader defaults in the options' do
      options = parse.to_options

      assert_instance_of Riffer::Rig::Loader::Options, options
    end
  end
end
