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
      assert_equal 'unexpected argument: hello extra', parse('-p', 'hello', 'extra')
    end

    it 'refuses a bare -r with -p' do
      assert_equal 'missing argument: -r', parse('-p', '-r')
    end

    it 'refuses a bare -r followed by a flag with -p' do
      assert_equal 'missing argument: -r', parse('-r', '-p', 'hello')
    end

    it 'refuses a bare -r clustered after -p' do
      assert_equal 'missing argument: -r', parse('-pr')
    end

    it 'refuses a zero --max-steps' do
      assert_equal 'invalid argument: --max-steps 0', parse('--max-steps', '0')
    end

    it 'refuses a negative --max-steps' do
      assert_equal 'invalid argument: --max-steps -1', parse('--max-steps', '-1')
    end

    it 'refuses a negative --job-idle-timeout' do
      assert_equal 'invalid argument: --job-idle-timeout -1', parse('-p', '--job-idle-timeout', '-1')
    end

    it 'refuses --verbose without -p' do
      assert_equal '--verbose is only available with -p', parse('--verbose')
    end

    it 'refuses --json without -p' do
      assert_equal '--json is only available with -p', parse('--json')
    end

    it 'refuses --job-idle-timeout without -p' do
      assert_equal '--job-idle-timeout is only available with -p', parse('--job-idle-timeout', '30')
    end

    it 'accepts the headless-only flags with -p' do
      assert_kind_of Riffer::Rig::CLI::Flags, parse('-p', '--verbose', '--json', '--job-idle-timeout', '30')
    end

    it 'leaves a headless-only flag to --help without -p' do
      assert parse('--verbose', '--help').help
    end

    it 'leaves a headless-only flag to --version without -p' do
      assert parse('--json', '--version').version
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

    it 'leaves the reasoning level to the Loader by default' do
      assert_nil parse.reasoning
    end

    it 'reads --reasoning' do
      assert_equal 'high', parse('--reasoning', 'high').reasoning
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
      assert parse('-p', '--verbose').verbose
    end

    it 'keeps --verbose off by default' do
      refute parse.verbose
    end

    it 'reads --job-idle-timeout as an integer' do
      assert_equal 30, parse('-p', '--job-idle-timeout', '30').job_idle_timeout
    end

    it 'leaves the job idle timeout to headless by default' do
      assert_nil parse.job_idle_timeout
    end

    it 'reads -p as headless' do
      assert parse('-p').headless
    end

    it 'reads --print as headless' do
      assert parse('--print').headless
    end

    it 'reads an abbreviated --print as headless' do
      assert parse('--pri').headless
    end

    it 'reads -p clustered before another short flag as headless' do
      assert parse('-pc').headless
    end

    it 'reads -p clustered after another short flag as headless' do
      assert parse('-cp').headless
    end

    it 'keeps headless off by default' do
      refute parse.headless
    end

    it 'takes the prompt positional with -p' do
      assert_equal 'hello', parse('-p', 'hello').prompt
    end

    it 'takes the prompt positional with a clustered -p' do
      assert_equal 'hello', parse('-pc', 'hello').prompt
    end

    it 'takes the prompt positional after a clustered -pr id' do
      assert_equal 'hello', parse('-pr', 'abc', 'hello').prompt
    end

    it 'leaves the prompt to stdin without an argument' do
      assert_nil parse('-p').prompt
    end

    it 'reads -c clustered with -p' do
      assert parse('-pc').continue
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
      assert_equal 'abc', parse('-p', '-r', 'abc').resume
    end

    it 'reads the id after a clustered -pr' do
      assert_equal 'abc', parse('-pr', 'abc').resume
    end

    it 'reads the rest of a cluster after -r as the id' do
      assert_equal 'p', parse('-rp').resume
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

    it 'reads --version' do
      assert_predicate parse('--version'), :version
    end

    it 'reads -v as --version' do
      assert_predicate parse('-v'), :version
    end
  end

  describe '.usage' do
    it 'lists every flag in the usage' do
      usage = Riffer::Rig::CLI::Flags.usage

      assert(
        %w[
          --model --reasoning --no-extensions --no-skills --no-agents-md --tools --max-steps
          -p --verbose --job-idle-timeout --version
        ].all? do |flag|
          usage.include?(flag)
        end
      )
    end
  end

  describe '#to_options' do
    it 'builds the Loader options from the flags' do
      options = parse(
        '--model', 'openai/gpt-5', '--reasoning', 'high', '--no-skills', '--tools', 'read,bash', '--max-steps', '5'
      ).to_options

      assert_equal ['openai/gpt-5', 'high', false, %w[read bash], 5],
                   [options.model, options.reasoning, options.skills, options.tools, options.max_steps]
    end

    it 'keeps the Loader defaults in the options' do
      options = parse.to_options

      assert_instance_of Riffer::Rig::Loader::Options, options
    end
  end
end
