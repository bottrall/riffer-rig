# frozen_string_literal: true

require 'optparse'

class Riffer::Rig::CLI::Flags
  BANNER = <<~TEXT.chomp #: String
    Usage: riffer [options]
           riffer -p [prompt]   run one prompt headless and exit
           riffer acp           (not available yet)
  TEXT

  # @dynamic model, extensions, skills, agents_md, tools, max_steps, help, save, verbose, prompt, continue, resume
  attr_reader :model #: String?
  attr_reader :extensions, :skills, :agents_md, :help, :verbose #: bool
  attr_reader :tools #: Array[String]?
  attr_reader :max_steps #: Integer?
  attr_reader :save #: bool
  attr_reader :prompt #: String?
  attr_reader :continue #: bool
  attr_reader :resume #: String?

  # @rbs argv: Array[String]
  # @rbs prompt: bool
  # @rbs return: Riffer::Rig::CLI::Flags | String
  def self.parse(argv, prompt: false)
    values = {} #: Hash[Symbol, untyped]
    rest = parser.parse(argv, into: values)
    allowed = rest.empty? || (prompt && rest.size == 1)
    return "unexpected argument: #{rest.join(' ')}" unless allowed

    new(
      model: values[:model],
      extensions: !values.key?(:'no-extensions'),
      skills: !values.key?(:'no-skills'),
      agents_md: !values.key?(:'no-agents-md'),
      tools: values[:tools],
      max_steps: values[:'max-steps'],
      save: !values.key?(:'no-save'),
      verbose: values.key?(:verbose),
      prompt: prompt ? rest.first : nil,
      continue: values.key?(:continue),
      resume: values[:resume],
      help: values.key?(:help)
    )
  rescue OptionParser::ParseError => e
    e.message
  end

  # @rbs return: String
  def self.usage
    parser.help
  end

  # @rbs return: OptionParser
  def self.parser
    OptionParser.new do |parser|
      parser.banner = BANNER
      parser.separator('')
      parser.on('--model PROVIDER/NAME', String, 'Model for this session, over RIFFER_MODEL and settings')
      parser.on('--no-extensions', 'Skip extension files and autoload; the bundle still loads')
      parser.on('--no-skills', 'Leave out Agent Skills')
      parser.on('--no-agents-md', 'Leave out AGENTS.md instructions')
      parser.on('--tools NAME,NAME', Array, 'Only these tools, by identifier')
      parser.on('--max-steps N', Integer, 'Stop a turn after N model calls')
      parser.on('--no-save', 'Do not save this session')
      parser.on('-c', '--continue', 'Continue the most recent session in this directory')
      parser.on('-r ID', '--resume ID', String, 'Resume the session with this id')
      parser.on('-p', '--print', 'Run one prompt headless and exit; the prompt is the argument, else stdin')
      parser.on('--verbose', 'With -p, trace each tool call to stderr')
      parser.on('-h', '--help', 'Show this help')
    end
  end
  private_class_method :parser

  # @rbs model: String?
  # @rbs extensions: bool
  # @rbs skills: bool
  # @rbs agents_md: bool
  # @rbs tools: Array[String]?
  # @rbs max_steps: Integer?
  # @rbs save: bool
  # @rbs verbose: bool
  # @rbs prompt: String?
  # @rbs continue: bool
  # @rbs resume: String?
  # @rbs help: bool
  # @rbs return: void
  def initialize(
    model: nil,
    extensions: true,
    skills: true,
    agents_md: true,
    tools: nil,
    max_steps: nil,
    save: true,
    verbose: false,
    prompt: nil,
    continue: false,
    resume: nil,
    help: false
  )
    @model = model
    @extensions = extensions
    @skills = skills
    @agents_md = agents_md
    @tools = tools&.freeze
    @max_steps = max_steps
    @save = save
    @verbose = verbose
    @prompt = prompt
    @continue = continue
    @resume = resume
    @help = help
    freeze
  end
end
