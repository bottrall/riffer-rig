# frozen_string_literal: true

require 'optparse'

class Riffer::Rig::CLI::Flags
  BANNER = <<~TEXT.chomp #: String
    Usage: riffer [options]
           riffer -p [prompt]   run one prompt headless and exit
           riffer acp           serve Runtimes as an ACP agent over stdio
  TEXT

  HEADLESS_ONLY = %i[verbose json job-idle-timeout].freeze #: Array[Symbol]

  # @dynamic model, reasoning, extensions, skills, agents_md, tools, max_steps, help, version
  # @dynamic save, verbose, json, job_idle_timeout, headless, prompt, continue, resume
  attr_reader :model #: String?
  attr_reader :reasoning #: String?
  attr_reader :extensions, :skills, :agents_md, :help, :version, :verbose, :json, :headless #: bool
  attr_reader :tools #: Array[String]?
  attr_reader :max_steps #: Integer?
  attr_reader :save #: bool
  attr_reader :job_idle_timeout #: Integer?
  attr_reader :prompt #: String?
  attr_reader :continue #: bool
  attr_reader :resume #: String?

  # @rbs argv: Array[String]
  # @rbs return: Riffer::Rig::CLI::Flags | String
  def self.parse(argv)
    values = {} #: Hash[Symbol, untyped]
    rest = parser.parse(argv, into: values)
    flags = assemble(values, rest.first)
    allowed = rest.empty? || (flags.headless && rest.size == 1)
    return "unexpected argument: #{rest.join(' ')}" unless allowed
    return 'missing argument: -r' if flags.headless && flags.resume == ''
    return "invalid argument: --max-steps #{flags.max_steps}" if flags.max_steps&.<(1)
    return "invalid argument: --job-idle-timeout #{flags.job_idle_timeout}" if flags.job_idle_timeout&.negative?

    stray = HEADLESS_ONLY.find { |key| values.key?(key) } unless flags.headless || flags.help || flags.version
    return "--#{stray} is only available with -p" if stray

    flags
  rescue OptionParser::ParseError => e
    e.message
  end

  # @rbs return: String
  def self.usage
    parser.help
  end

  # @rbs return: Riffer::Rig::Loader::Options
  def to_options
    Riffer::Rig::Loader::Options.new(
      model: model,
      reasoning: reasoning,
      extensions: extensions,
      skills: skills,
      agents_md: agents_md,
      tools: tools,
      max_steps: max_steps
    )
  end

  # @rbs return: OptionParser
  def self.parser
    OptionParser.new do |parser|
      parser.banner = BANNER
      parser.separator('')
      parser.on('--model PROVIDER/NAME', String, 'Model for this session, over RIFFER_MODEL and settings')
      parser.on('--reasoning LEVEL', String, 'Reasoning level for this session, over RIFFER_REASONING and settings')
      parser.on('--no-extensions', 'Skip extension files and autoload; the bundle still loads')
      parser.on('--no-skills', 'Leave out Agent Skills')
      parser.on('--no-agents-md', 'Leave out AGENTS.md instructions')
      parser.on('--tools NAME,NAME', Array, 'Only these tools, by identifier')
      parser.on('--max-steps N', Integer, 'Stop a turn after N model calls')
      parser.on('--no-save', 'Do not save this session')
      parser.on('-c', '--continue', 'Continue the most recent session in this directory')
      parser.on(
        '-r [ID]',
        '--resume [ID]',
        String,
        'Resume the session with this id; bare -r opens the picker in the REPL'
      ) { |id| id || '' }
      parser.on('-p', '--print', 'Run one prompt headless and exit; the prompt is the argument, else stdin')
      parser.on('--verbose', 'With -p, trace each tool call to stderr')
      parser.on('--json', 'With -p, stream every Runtime event as NDJSON to stdout')
      parser.on(
        '--job-idle-timeout SECONDS',
        Integer,
        'With -p, kill background jobs once none has exited for SECONDS (default 600; 0 waits indefinitely)'
      )
      parser.on('-h', '--help', 'Show this help')
      parser.on('-v', '--version', 'Show the version')
    end
  end
  private_class_method :parser

  # @rbs values: Hash[Symbol, untyped]
  # @rbs prompt: String?
  # @rbs return: Riffer::Rig::CLI::Flags
  def self.assemble(values, prompt)
    new(
      model: values[:model],
      reasoning: values[:reasoning],
      extensions: !values.key?(:'no-extensions'),
      skills: !values.key?(:'no-skills'),
      agents_md: !values.key?(:'no-agents-md'),
      tools: values[:tools],
      max_steps: values[:'max-steps'],
      save: !values.key?(:'no-save'),
      verbose: values.key?(:verbose),
      json: values.key?(:json),
      job_idle_timeout: values[:'job-idle-timeout'],
      headless: values.key?(:print),
      prompt: prompt,
      continue: values.key?(:continue),
      resume: values[:resume],
      help: values.key?(:help),
      version: values.key?(:version)
    )
  end
  private_class_method :assemble

  # @rbs model: String?
  # @rbs reasoning: String?
  # @rbs extensions: bool
  # @rbs skills: bool
  # @rbs agents_md: bool
  # @rbs tools: Array[String]?
  # @rbs max_steps: Integer?
  # @rbs save: bool
  # @rbs verbose: bool
  # @rbs json: bool
  # @rbs job_idle_timeout: Integer?
  # @rbs headless: bool
  # @rbs prompt: String?
  # @rbs continue: bool
  # @rbs resume: String?
  # @rbs help: bool
  # @rbs version: bool
  # @rbs return: void
  def initialize(
    model: nil,
    reasoning: nil,
    extensions: true,
    skills: true,
    agents_md: true,
    tools: nil,
    max_steps: nil,
    save: true,
    verbose: false,
    json: false,
    job_idle_timeout: nil,
    headless: false,
    prompt: nil,
    continue: false,
    resume: nil,
    help: false,
    version: false
  )
    @model = model
    @reasoning = reasoning
    @extensions = extensions
    @skills = skills
    @agents_md = agents_md
    @tools = tools&.freeze
    @max_steps = max_steps
    @save = save
    @verbose = verbose
    @json = json
    @job_idle_timeout = job_idle_timeout
    @headless = headless
    @prompt = prompt
    @continue = continue
    @resume = resume
    @help = help
    @version = version
    freeze
  end
end
