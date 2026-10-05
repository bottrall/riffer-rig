# frozen_string_literal: true

module Riffer::Rig::CLI
  extend self

  PRINT_FLAGS = %w[-p --print].freeze #: Array[String]

  ACP_COMMAND = 'acp'

  USAGE_ERROR = 2

  # @rbs argv: Array[String]
  # @rbs input: IO
  # @rbs output: IO
  # @rbs error: IO
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs cwd: String
  # @rbs home: String
  # @rbs return: Integer
  def start(
    argv = ARGV,
    input: $stdin,
    output: $stdout,
    error: $stderr,
    env: Riffer::Rig::Env.load,
    cwd: Dir.pwd,
    home: Dir.home
  )
    return unavailable("riffer #{ACP_COMMAND}", error) if argv.first == ACP_COMMAND

    headless_mode = argv.intersect?(PRINT_FLAGS)
    flags = Flags.parse(argv, prompt: headless_mode)
    return refuse(flags, error) if flags.is_a?(String)
    return help(output) if flags.help
    return refuse('--verbose is only available with -p', error) if flags.verbose && !headless_mode

    return headless(flags, input:, output:, error:, env:, cwd:, home:) if headless_mode

    terminal(flags, input:, output:, env:, cwd:, home:)
  end

  private

  # @rbs flags: Riffer::Rig::CLI::Flags
  # @rbs input: IO
  # @rbs output: IO
  # @rbs error: IO
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs cwd: String
  # @rbs home: String
  # @rbs return: Integer
  def headless(flags, input:, output:, error:, env:, cwd:, home:)
    Riffer::Rig::Headless.for(
      input: input,
      output: output,
      error: error,
      verbose: flags.verbose
    ).run(prompt: flags.prompt) do |host|
      loader = new_loader(flags, host: host, env: env, cwd: cwd, home: home)
      started = find_session(flags, loader)
      raise Riffer::Rig::Loader::ConfigurationError, missing_session(flags) if started.nil? && session_flags?(flags)

      started || build(loader, flags)
    end
  end

  # @rbs flags: Riffer::Rig::CLI::Flags
  # @rbs input: IO
  # @rbs output: IO
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs cwd: String
  # @rbs home: String
  # @rbs return: Integer
  def terminal(flags, input:, output:, env:, cwd:, home:)
    Riffer::Rig::Terminal.for(
      input: input,
      output: output,
      version: Riffer::Rig::VERSION,
      no_color: env.is_a?(Riffer::Rig::Env) && env.no_color
    ).run do |host|
      loader = new_loader(flags, host: host, env: env, cwd: cwd, home: home)
      started = find_session(flags, loader)
      host.notify(missing_session(flags)) if started.nil? && session_flags?(flags)

      started || build(loader, flags)
    end
  end

  # @rbs flags: Riffer::Rig::CLI::Flags
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs cwd: String
  # @rbs home: String
  # @rbs return: Riffer::Rig::Loader
  def new_loader(flags, host:, env:, cwd:, home:)
    Riffer::Rig::Loader.new(
      cwd: cwd,
      host: host,
      env: env,
      home: home,
      store: flags.save ? Riffer::Rig::Stores::JSONL.new : nil
    )
  end

  # @rbs flags: Riffer::Rig::CLI::Flags
  # @rbs loader: Riffer::Rig::Loader
  # @rbs return: Riffer::Rig::Runtime?
  def find_session(flags, loader)
    if flags.resume
      loader.resume(flags.resume, **keywords(flags))
    elsif flags.continue
      loader.continue(**keywords(flags))
    end
  end

  # @rbs flags: Riffer::Rig::CLI::Flags
  # @rbs return: bool
  def session_flags?(flags)
    flags.resume ? true : flags.continue
  end

  # @rbs flags: Riffer::Rig::CLI::Flags
  # @rbs return: String
  def missing_session(flags)
    flags.resume ? "No saved session #{flags.resume}." : 'No saved session in this directory.'
  end

  # @rbs loader: Riffer::Rig::Loader
  # @rbs flags: Riffer::Rig::CLI::Flags
  # @rbs return: Riffer::Rig::Runtime
  def build(loader, flags)
    loader.runtime(**keywords(flags))
  end

  # @rbs flags: Riffer::Rig::CLI::Flags
  # @rbs return: Hash[Symbol, untyped]
  def keywords(flags)
    {
      model: flags.model,
      extensions: flags.extensions,
      skills: flags.skills,
      agents_md: flags.agents_md,
      tools: flags.tools,
      max_steps: flags.max_steps
    }
  end

  # @rbs name: String
  # @rbs error: IO
  # @rbs return: Integer
  def unavailable(name, error)
    refuse("#{name} is not available yet", error)
  end

  # @rbs message: String
  # @rbs error: IO
  # @rbs return: Integer
  def refuse(message, error)
    error.puts("riffer: #{message}")
    error.puts(Flags.usage)
    USAGE_ERROR
  end

  # @rbs output: IO
  # @rbs return: Integer
  def help(output)
    output.puts(Flags.usage)
    0
  end
end
