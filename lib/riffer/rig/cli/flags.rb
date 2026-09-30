# frozen_string_literal: true

require 'optparse'

class Riffer::Rig::CLI::Flags
  BANNER = <<~TEXT.chomp #: String
    Usage: riffer [options]
           riffer -p [prompt]   (not available yet)
           riffer acp           (not available yet)
  TEXT

  # @dynamic model, extensions, skills, agents_md, tools, max_steps, help
  attr_reader :model #: String?
  attr_reader :extensions, :skills, :agents_md, :help #: bool
  attr_reader :tools #: Array[String]?
  attr_reader :max_steps #: Integer?

  # @rbs argv: Array[String]
  # @rbs return: Riffer::Rig::CLI::Flags | String
  def self.parse(argv)
    values = {} #: Hash[Symbol, untyped]
    rest = parser.parse(argv, into: values)
    return "unexpected argument: #{rest.join(' ')}" unless rest.empty?

    new(
      model: values[:model],
      extensions: !values.key?(:'no-extensions'),
      skills: !values.key?(:'no-skills'),
      agents_md: !values.key?(:'no-agents-md'),
      tools: values[:tools],
      max_steps: values[:'max-steps'],
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
  # @rbs help: bool
  # @rbs return: void
  def initialize(model: nil, extensions: true, skills: true, agents_md: true, tools: nil, max_steps: nil, help: false)
    @model = model
    @extensions = extensions
    @skills = skills
    @agents_md = agents_md
    @tools = tools&.freeze
    @max_steps = max_steps
    @help = help
    freeze
  end
end
