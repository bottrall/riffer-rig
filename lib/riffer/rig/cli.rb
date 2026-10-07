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
    return refuse("#{ACP_COMMAND} takes no arguments", error) if argv.first == ACP_COMMAND && argv.length > 1
    return acp(input: input, output: output, env: env, home: home) if argv.first == ACP_COMMAND

    headless_mode = argv.intersect?(PRINT_FLAGS)
    flags = Flags.parse(argv, prompt: headless_mode)
    return refuse(flags, error) if flags.is_a?(String)
    return help(output) if flags.help
    return refuse('--verbose is only available with -p', error) if flags.verbose && !headless_mode
    return refuse('--json is only available with -p', error) if flags.json && !headless_mode

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
    sessions = Sessions.new(flags: flags, env: env, cwd: cwd, home: home)
    Riffer::Rig::Headless.for(
      input: input,
      output: output,
      error: error,
      verbose: flags.verbose,
      json: flags.json
    ).run(prompt: flags.prompt) do |host|
      started = sessions.find(host)
      raise Riffer::Rig::Loader::ConfigurationError, sessions.missing if started.nil? && sessions.asked?

      started || sessions.fresh(host)
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
      no_color: env.is_a?(Riffer::Rig::Env) && env.no_color,
      sessions: Sessions.new(flags: flags, env: env, cwd: cwd, home: home)
    ).run(open_picker: flags.resume == '')
  end

  # @rbs input: IO
  # @rbs output: IO
  # @rbs env: Riffer::Rig::Env | Riffer::Rig::Env::Invalid
  # @rbs home: String
  # @rbs return: Integer
  def acp(input:, output:, env:, home:)
    Riffer::Rig::ACP.for(input: input, output: output, env: env, home: home).run
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
