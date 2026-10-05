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
    return unavailable('riffer -p', error) if argv.intersect?(PRINT_FLAGS)

    flags = Flags.parse(argv)
    return refuse(flags, error) if flags.is_a?(String)
    return help(output) if flags.help

    terminal(flags, input:, output:, env:, cwd:, home:)
  end

  private

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
      loader = Riffer::Rig::Loader.new(
        cwd: cwd,
        host: host,
        env: env,
        home: home,
        store: flags.save ? Riffer::Rig::Stores::JSONL.new : nil
      )
      resumed(flags, host, loader) || build(loader, flags)
    end
  end

  # @rbs flags: Riffer::Rig::CLI::Flags
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs loader: Riffer::Rig::Loader
  # @rbs return: Riffer::Rig::Runtime?
  def resumed(flags, host, loader)
    if flags.resume
      started = loader.resume(flags.resume, **keywords(flags))
      host.notify("No saved session #{flags.resume}.") unless started
      started
    elsif flags.continue
      started = loader.continue(**keywords(flags))
      host.notify('No saved session in this directory.') unless started
      started
    end
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
