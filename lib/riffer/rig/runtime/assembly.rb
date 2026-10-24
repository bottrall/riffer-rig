# frozen_string_literal: true

class Riffer::Rig::Runtime::Assembly
  # @rbs @extension_commands: Array[Riffer::Rig::Command]
  # @rbs @skill_sources: Array[^(Riffer::Rig::Runtime) -> Riffer::Skills::Backend]

  # @dynamic failures, tools, hooks, mcp_declarations, prompt_sections, declared_settings, settings
  attr_reader :failures #: Array[Riffer::Rig::Extension::Failure]
  attr_reader :tools #: Array[singleton(Riffer::Tool)]
  attr_reader :hooks #: Hash[Symbol, Array[^(Riffer::Rig::Events::_Event | ::Riffer::StreamEvents::Base) -> untyped]]
  attr_reader :mcp_declarations #: Hash[String, Riffer::Rig::Mcp::Declaration]
  attr_reader :prompt_sections #: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  attr_reader :declared_settings #: Hash[Symbol, Hash[Symbol, untyped]]
  attr_reader :settings #: Hash[Symbol, untyped]

  # @dynamic overrides, unknown_tools
  attr_reader :overrides #: Array[String]
  attr_reader :unknown_tools #: Array[String]

  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs allowlist: Array[String]?
  # @rbs strict: bool
  # @rbs return: void
  def initialize(extensions, settings, allowlist, strict: false)
    outcomes = extensions.map { |extension| trial(extension, settings, strict) }
    registrars = outcomes.grep(Riffer::Rig::Registrar) #: Array[Riffer::Rig::Registrar]
    @failures = outcomes.grep(Riffer::Rig::Extension::Failure) #: Array[Riffer::Rig::Extension::Failure]
    @tools = select_tools(registrars.flat_map { |registrar| registrar.tools.to_a }.to_h.values, allowlist)
    @hooks = merge_hooks(registrars)
    @mcp_declarations = registrars.flat_map { |registrar| registrar.mcp_servers.to_a }.to_h
    @prompt_sections = registrars.flat_map { |registrar| registrar.prompts.to_a }.to_h
    @declared_settings = registrars.to_h { |registrar| [registrar.extension.to_sym, registrar.declared_settings] }
                                   .reject { |_extension, declared| declared.empty? }
    @settings = with_declared_defaults(settings, @declared_settings)
    @overrides = overrides_of(registrars)
    @unknown_tools = unknown_tools_of(registrars, allowlist)
    @extension_commands = registrars.flat_map { |registrar| registrar.commands.values }
    @skill_sources = registrars.flat_map(&:skill_sources)
    freeze
  end

  # @rbs runtime: Riffer::Rig::Runtime
  # @rbs return: Riffer::Skills::Config?
  def skills_config(runtime)
    return if @skill_sources.empty?

    config = Riffer::Skills::Config.new
    config.backend(Riffer::Rig::Skills::Sources.new(@skill_sources.map { |source| source.call(runtime) }))
    config
  end

  # @rbs core: Array[Riffer::Rig::Command]
  # @rbs skills: Array[Riffer::Skills::Frontmatter]
  # @rbs return: Hash[String, Riffer::Rig::Command]
  def commands(core, skills)
    [
      *core,
      *skills.map { |skill| Riffer::Rig::Commands::Skill.command(skill) },
      *@extension_commands
    ].to_h { |command| [command.name, command] }
  end

  private

  # @rbs extension: Riffer::Rig::Extension
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs strict: bool
  # @rbs return: (Riffer::Rig::Registrar | Riffer::Rig::Extension::Failure)
  def trial(extension, settings, strict)
    outcome = extension.trial(settings)
    return outcome if outcome.is_a?(Riffer::Rig::Registrar)
    raise outcome if strict

    Riffer::Rig::Extension::Failure.new(extension: extension, error: outcome)
  end

  # @rbs registered: Array[singleton(Riffer::Tool)]
  # @rbs allowlist: Array[String]?
  # @rbs return: Array[singleton(Riffer::Tool)]
  def select_tools(registered, allowlist)
    return registered if allowlist.nil?

    registered.select { |klass| allowlist.include?(klass.name) }
  end

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs return: Hash[Symbol, Array[^(Riffer::Rig::Events::_Event | ::Riffer::StreamEvents::Base) -> untyped]]
  def merge_hooks(registrars)
    Riffer::Rig::Registrar::EVENTS.to_h do |event|
      [event, registrars.flat_map { |registrar| registrar.hooks.fetch(event) }]
    end
  end

  # @rbs settings: Hash[Symbol, untyped]
  # @rbs declared: Hash[Symbol, Hash[Symbol, untyped]]
  # @rbs return: Hash[Symbol, untyped]
  def with_declared_defaults(settings, declared)
    namespaces = declared.to_h do |extension, defaults|
      given = settings[extension] || {} #: Hash[Symbol, untyped]
      [extension, defaults.merge(given)]
    end
    settings.merge(namespaces)
  end

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs return: Array[String]
  def overrides_of(registrars)
    registrars
      .flat_map { |registrar| registrar.registrations.map { |registration| [registration, registrar.extension] } }
      .group_by(&:first)
      .flat_map do |registration, claims|
        claims.map(&:last).each_cons(2).map do |earlier, later|
          "Extension #{later} replaces #{registration} from #{earlier}"
        end
      end
  end

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs allowlist: Array[String]?
  # @rbs return: Array[String]
  def unknown_tools_of(registrars, allowlist)
    return [] if allowlist.nil?

    registered = registrars.flat_map { |registrar| registrar.tools.keys }
    (allowlist - registered).map { |name| "Unknown tool in allowlist: #{name}" }
  end
end
