# frozen_string_literal: true

class Riffer::Rig::Registrar
  class NameCollisionError < StandardError; end

  CORE_SETTINGS_KEYS = %w[model reasoning models reload extensions sessions providers mcp tools].freeze #: Array[String]

  EVENTS = %i[
    session_start session_end
    before_prompt before_tool_call before_request
    after_tool_call after_response turn_end
    stream
  ].freeze #: Array[Symbol]

  # @rbs @tools: Hash[String, singleton(Riffer::Tool)]
  # @rbs @prompts: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  # @rbs @commands: Hash[String, Riffer::Rig::Command]
  # @rbs @settings: Hash[Symbol, untyped]
  # @rbs @handlers: Hash[Symbol, Array[^(Riffer::Rig::Events::Event | ::Riffer::StreamEvents::Base) -> untyped]]

  # @dynamic extension
  attr_reader :extension #: String

  # @rbs extension: String
  # @rbs return: void
  def initialize(extension)
    @extension = extension
    @tools = {}
    @prompts = {}
    @commands = {}
    @settings = {}
    @handlers = EVENTS.to_h { |event| [event, []] }
  end

  # @rbs return: NameCollisionError?
  def collision
    return unless CORE_SETTINGS_KEYS.include?(@extension)

    NameCollisionError.new("extension name #{@extension} collides with a core settings key")
  end

  # @rbs klass: singleton(Riffer::Tool)
  # @rbs return: void
  def tool(klass)
    @tools[klass.identifier] = klass
  end

  # @rbs name: Symbol
  # @rbs &block: (Riffer::Rig::Runtime) -> String?
  # @rbs return: void
  def prompt(name, &block)
    @prompts[name] = block
  end

  # @rbs name: String
  # @rbs description: String
  # @rbs &block: (Riffer::Rig::Command::Context) -> void
  # @rbs return: void
  def command(name, description:, &)
    @commands[name] = Riffer::Rig::Command.new(name, description: description, extension: @extension, &)
  end

  # @rbs key: Symbol
  # @rbs default: untyped
  # @rbs return: void
  def setting(key, default:)
    @settings[key] = default
  end

  # @rbs event: Symbol
  # @rbs &block: (Riffer::Rig::Events::Event | ::Riffer::StreamEvents::Base) -> untyped
  # @rbs return: void
  def on(event, &block)
    handlers = @handlers.fetch(event) do
      raise Riffer::ArgumentError, "unknown event #{event.inspect}; expected one of #{EVENTS.join(', ')}"
    end
    handlers << block
  end

  # @rbs return: Hash[String, singleton(Riffer::Tool)]
  def tools
    @tools.dup
  end

  # @rbs return: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  def prompts
    @prompts.dup
  end

  # @rbs return: Hash[String, Riffer::Rig::Command]
  def commands
    @commands.dup
  end

  # @rbs return: Hash[Symbol, untyped]
  def settings
    @settings.dup
  end

  # @rbs return: Array[String]
  def registrations
    [
      *@tools.keys.map { |identifier| "tool #{identifier}" },
      *@prompts.keys.map { |name| "prompt section #{name}" },
      *@commands.keys.map { |name| "command #{name}" }
    ]
  end

  # @rbs return: Hash[Symbol, Array[^(Riffer::Rig::Events::Event | ::Riffer::StreamEvents::Base) -> untyped]]
  def handlers
    @handlers.transform_values(&:dup)
  end
end
