# frozen_string_literal: true

class Riffer::Rig::Registrar
  class NameCollisionError < StandardError; end

  CORE_SETTINGS_KEYS = %w[model reasoning models reload extensions sessions providers tools].freeze #: Array[String]

  EVENTS = %i[
    session_start session_end
    before_prompt before_tool_call before_request
    after_tool_call after_response turn_end
    stream
  ].freeze #: Array[Symbol]

  # @rbs @tools: Hash[String, singleton(Riffer::Tool)]
  # @rbs @prompts: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  # @rbs @commands: Hash[String, Riffer::Rig::Command]
  # @rbs @skill_sources: Array[^(Riffer::Rig::Runtime) -> Riffer::Skills::Backend]
  # @rbs @declared_settings: Hash[Symbol, untyped]
  # @rbs @given_settings: Hash[Symbol, untyped]
  # @rbs @mcp_servers: Hash[String, Riffer::Rig::Mcp::Declaration]
  # @rbs @hooks: Hash[Symbol, Array[^(Riffer::Rig::Events::_Event | ::Riffer::StreamEvents::Base) -> untyped]]

  # @dynamic extension
  attr_reader :extension #: String

  # @rbs extension: String
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs return: void
  def initialize(extension, settings = {})
    @extension = extension
    @tools = {}
    @prompts = {}
    @commands = {}
    @skill_sources = []
    @declared_settings = {}
    @given_settings = settings
    @mcp_servers = {}
    @hooks = EVENTS.to_h { |event| [event, []] }
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

  # @rbs &block: (Riffer::Rig::Runtime) -> Riffer::Skills::Backend
  # @rbs return: void
  def skills(&block)
    @skill_sources << block
  end

  # @rbs key: Symbol
  # @rbs default: untyped
  # @rbs return: void
  def setting(key, default:)
    @declared_settings[key] = default
  end

  # @rbs name: String
  # @rbs url: String
  # @rbs headers: Hash[String, String]
  # @rbs auth: Hash[Symbol, (String | Array[String])]
  # @rbs return: void
  def mcp(name, url:, headers: {}, auth: {})
    fields = auth.transform_keys(&:to_sym)
                 .transform_values { |env_names| env_names.is_a?(String) ? [env_names] : env_names }
    @mcp_servers[name] = Riffer::Rig::Mcp::Declaration.new(url: url, headers: headers, auth: fields)
  end

  # @rbs prefix: String | Symbol
  # @rbs setup: Riffer::Rig::ProviderSetup | Hash[Symbol, untyped]?
  # @rbs &block: () -> singleton(::Riffer::Providers::Base)
  # @rbs return: void
  def provider(prefix, setup: nil, &)
    Riffer::Rig::Providers.register(prefix, setup:, &)
  end

  # @rbs event: Symbol
  # @rbs &block: (Riffer::Rig::Events::_Event | ::Riffer::StreamEvents::Base) -> untyped
  # @rbs return: void
  def on(event, &block)
    hooks = @hooks.fetch(event) do
      raise Riffer::ArgumentError, "unknown event #{event.inspect}; expected one of #{EVENTS.join(', ')}"
    end
    hooks << block
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

  # @rbs return: Array[^(Riffer::Rig::Runtime) -> Riffer::Skills::Backend]
  def skill_sources
    @skill_sources.dup
  end

  # @rbs return: Hash[Symbol, untyped]
  def settings
    @declared_settings.merge(@given_settings)
  end

  # @rbs return: Hash[Symbol, untyped]
  def declared_settings
    @declared_settings.dup
  end

  # @rbs return: Hash[String, Riffer::Rig::Mcp::Declaration]
  def mcp_servers
    @mcp_servers.dup
  end

  # @rbs return: Array[String]
  def registrations
    [
      *@tools.keys.map { |identifier| "tool #{identifier}" },
      *@prompts.keys.map { |name| "prompt section #{name}" },
      *@commands.keys.map { |name| "command #{name}" },
      *@mcp_servers.keys.map { |name| "MCP server #{name}" }
    ]
  end

  # @rbs return: Hash[Symbol, Array[^(Riffer::Rig::Events::_Event | ::Riffer::StreamEvents::Base) -> untyped]]
  def hooks
    @hooks.transform_values(&:dup)
  end
end
