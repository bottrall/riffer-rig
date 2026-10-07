# frozen_string_literal: true

require 'date'
require 'securerandom'

# Never renders, prints or reads the filesystem: anything a host needs is a
# Runtime feature, so embedders get it too.
class Riffer::Rig::Runtime
  class BusyError < StandardError; end

  class ClosedError < StandardError; end

  BASE_PROMPT_TEMPLATE = <<~TEXT
    You are %<name>s, a general-purpose agent. You work by using the tools you have
    been given; each tool describes what it does and when to use it.

    - Verify with your tools before answering. When a tool can settle a question,
      look rather than guess.
    - Do what was asked, and all of what was asked. Do not widen the scope, tidy
      nearby things, or add extras that were not requested.
    - Be concise. Lead with the outcome; do not restate the question.
  TEXT

  DEFAULT_NAME = 'riffer'

  # Unlimited: riffer's own default (16) is too small for a general-purpose
  # harness.
  DEFAULT_MAX_STEPS = nil #: Integer?

  INTERRUPT_CANCELLED = :cancelled #: Symbol

  # Upstream candidate: riffer's Anthropic, OpenAI and Azure OpenAI classes read
  # the web_search option and OpenRouter passes unknown options through to its
  # API, but the provider seam cannot yet answer which provider takes which
  # option, so rig keeps the mapping until it can. Mock consumes web_search, so
  # tests and embedders can exercise the switches.
  NATIVE_TOOLS_BY_PROVIDER = {
    web_search: { anthropic: true, openai: true, azure_openai: true, mock: true }.freeze
  }.freeze #: Hash[Symbol, Hash[Symbol, bool]]

  # @rbs @agent: Riffer::Agent
  # @rbs @base_prompt: String
  # @rbs @cancel_flag: Riffer::Rig::Runtime::CancelFlag
  # @rbs @credentials: Hash[Symbol, Hash[Symbol, String]]
  # @rbs @cwd: String
  # @rbs @host: Riffer::Rig::Hosts::Mirror
  # @rbs @id: String
  # @rbs @settings: Hash[Symbol, untyped]
  # @rbs @busy: bool
  # @rbs @closed: bool
  # @rbs @session_start_pending: bool
  # @rbs @session_start_reason: Symbol
  # @rbs @model_override: String?
  # @rbs @message_observers: Array[^(Riffer::Messages::Base) -> void]
  # @rbs @model_observers: Array[^(String) -> void]
  # @rbs @prompts: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  # @rbs @commands: Hash[String, Riffer::Rig::Command]
  # @rbs @core_commands: Array[Riffer::Rig::Command]
  # @rbs @claim_depth: Integer
  # @rbs @claim_thread: Thread?
  # @rbs @declared_settings: Hash[String, Hash[Symbol, untyped]]
  # @rbs @errors: Array[Riffer::Rig::Extension::Failure]
  # @rbs @hooks: Riffer::Rig::Runtime::Hooks
  # @rbs @tool_allowlist: Array[String]?
  # @rbs @mcp_registry: Riffer::Rig::Mcp::_Registry
  # @rbs @mcp_servers: Hash[String, Riffer::Rig::Mcp::Server]
  # @rbs @env: Riffer::Rig::Env
  # @rbs @auth_path: String
  # @rbs @model_options: Hash[Symbol, untyped]
  # @rbs @native_tools: Hash[Symbol, untyped]
  # @rbs @reload_check: (^(::Riffer::Rig::Runtime) -> void)?

  # @dynamic agent, credentials, cwd, host, id, settings, declared_settings
  attr_reader :agent #: Riffer::Agent
  attr_reader :credentials #: Hash[Symbol, Hash[Symbol, String]]
  attr_reader :cwd #: String
  attr_reader :host #: Riffer::Rig::Hosts::Mirror
  attr_reader :id #: String
  attr_reader :settings #: Hash[Symbol, untyped]
  attr_reader :declared_settings #: Hash[String, Hash[Symbol, untyped]]

  # @rbs model: String
  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs tools: Array[String]?
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs host: Riffer::Rig::Hosts::_Host
  # @rbs cwd: String?
  # @rbs name: String
  # @rbs instructions: String?
  # @rbs credentials: Hash[Symbol, Hash[Symbol, String]]
  # @rbs env: Riffer::Rig::Env
  # @rbs auth_path: String
  # @rbs pricing: Hash[String, Riffer::Rig::Settings::Pricing]
  # @rbs riffer_config: Riffer::Config
  # @rbs mcp_registry: Riffer::Rig::Mcp::_Registry
  # @rbs max_steps: Integer?
  # @rbs model_options: Hash[Symbol, untyped]
  # @rbs native_tools: Hash[Symbol, untyped]
  # @rbs snapshot: Hash[Symbol, untyped]?
  # @rbs return: void
  def initialize(
    model,
    extensions: [],
    tools: nil,
    settings: {},
    host: Riffer::Rig::Hosts::Null.new,
    cwd: nil,
    name: DEFAULT_NAME,
    instructions: nil,
    credentials: {},
    env: Riffer::Rig::Env.new,
    auth_path: Riffer::Rig::Credentials::PATH,
    pricing: {},
    riffer_config: Riffer.config,
    mcp_registry: Riffer::Mcp,
    max_steps: DEFAULT_MAX_STEPS,
    model_options: {},
    native_tools: {},
    snapshot: nil
  )
    # Doubles as the snapshot id and ACP sessionId.
    @id = snapshot ? snapshot.fetch(:id) : ::SecureRandom.uuid_v7
    @host = Riffer::Rig::Hosts::Mirror.new(host)
    @cwd = cwd || Dir.pwd
    @credentials = credentials
    @env = env
    @auth_path = auth_path

    @busy = false
    @closed = false
    @claim_depth = 0
    @claim_thread = nil
    @core_commands = []
    @reload_check = nil
    @cancel_flag = Riffer::Rig::Runtime::CancelFlag.new
    @session_start_pending = true
    @session_start_reason = snapshot ? :restore : :new
    @message_observers = []
    @model_observers = []
    Riffer::Rig::Settings::Pricing.register(pricing, riffer_config.pricing)
    @errors = []
    @tool_allowlist = tools
    @native_tools = native_tools
    @model_options = model_options.merge(native_options(model))
    @base_prompt = instructions || format(BASE_PROMPT_TEMPLATE, name: name)
    @mcp_registry = mcp_registry
    @mcp_servers = {}
    registrars = build_registrars(extensions, settings) { |extension, error| record_error(extension, error) }
    mcp_servers = register_mcp_servers(registrars)
    hooks = Riffer::Rig::Runtime::Hooks.new(merge_hooks(registrars), @host)
    config = agent_config(registrars, hooks, max_steps)
    agent = snapshot ? restore(snapshot, model, config) : build_agent(model, config)
    install(registrars, mcp_servers, settings, hooks, agent)
    @agent.session.on_message { |message| observe_message(message) }
  end

  # @rbs text: String
  # @rbs &block: ?(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void
  # @rbs return: (nil | Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event, Riffer::Agent::Response])
  def prompt(text, &block)
    claim
    begin
      if block
        turn(text).each(&block)
        nil
      else
        turn(text)
      end
    ensure
      release
    end
  end

  # @rbs text: String
  # @rbs return: Riffer::Agent::Response
  def ask(text)
    claim
    begin
      turn(text).each { |event| event }
    ensure
      release
    end
  end

  # @rbs return: Array[Riffer::Rig::Command]
  def commands
    @commands.values
  end

  # Installs a host-of-the-runtime command (the Loader's /reload) so it
  # survives every rebuild; an extension command of the same name replaces it.
  # @rbs command: Riffer::Rig::Command
  # @rbs return: nil
  def install_command(command)
    @core_commands << command
    @commands[command.name] = command
    nil
  end

  # Installs a host-of-the-runtime check (the Loader's automatic reload) so it
  # survives every rebuild. The Runtime calls it at both before_request
  # boundaries, before any handler runs, and ignores the result.
  # @rbs check: ^(::Riffer::Rig::Runtime) -> void
  # @rbs return: nil
  def install_reload_check(check)
    @reload_check = check
    nil
  end

  # @rbs name: String
  # @rbs args: String
  # @rbs &block: ?(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void
  # @rbs return: nil
  def run_command(name, args = '', &block)
    claim
    emit = block || ->(_event) {} #: ^(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void
    begin
      execute(name, args, emit)
    ensure
      release
    end
    @host.drain.each(&emit)
    nil
  end

  # @rbs return: Array[Riffer::Rig::Extension::Failure]
  def errors
    @errors.dup
  end

  # @rbs return: String
  def model
    "#{@agent.provider_name}/#{@agent.model_name}"
  end

  # @rbs model: String
  # @rbs return: void
  def model=(model)
    # Upstream candidate: riffer resolves the model Proc once, in Agent.new, so
    # a switch rebuilds the agent over the same session and config.
    agent = successor(model, @agent.config)
    rederive_options(model)
    @agent = agent
    @model_override = model
    @model_observers.each { |observer| observer.call(model) }
  end

  # @rbs provider: Symbol
  # @rbs values: Hash[Symbol, String]
  # @rbs return: void
  def merge_credentials(provider, values)
    @credentials = @credentials.merge(provider => values)
  end

  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs return: nil
  def rebuild(extensions:, settings:)
    claim_rebuild
    begin
      registrars = build_registrars(extensions, settings) { |_extension, error| raise error }
      mcp_servers = register_mcp_servers(registrars)
      hooks = Riffer::Rig::Runtime::Hooks.new(merge_hooks(registrars), @host)
      agent = successor(model, agent_config(registrars, hooks, @agent.config.max_steps))
      lifecycle(:session_end, Riffer::Rig::Events::SessionEnd.new(:reload))
      @errors = []
      dropped = @mcp_servers.except(*mcp_servers.keys)
      install(registrars, mcp_servers, settings, hooks, agent)
      unregister_mcp_servers(dropped)
      lifecycle(:session_start, Riffer::Rig::Events::SessionStart.new(@id, :reload))
    ensure
      release
    end
    nil
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { id: @id, messages: @agent.session.messages.map(&:to_h), model: @model_override, skills: activated_skills }
  end

  # @rbs &block: (Riffer::Messages::Base) -> void
  # @rbs return: nil
  def on_message(&block)
    @message_observers << block
    nil
  end

  # @rbs &block: (String) -> void
  # @rbs return: nil
  def on_model_change(&block)
    @model_observers << block
    nil
  end

  # @rbs return: nil
  def cancel
    @cancel_flag.set
    nil
  end

  # @rbs return: Riffer::Providers::TokenUsage?
  def tally
    @agent.context.token_usage
  end

  # @rbs return: void
  def close
    return if @closed

    # TODO: emit Riffer::Rig::Events::SessionEnd on the stream once the rebuild
    # ticket settles the stream's session_end reasons.
    @closed = true
    unregister_mcp_servers(@mcp_servers)
    @hooks.observe(:session_end, Riffer::Rig::Events::SessionEnd.new(:close)) unless @session_start_pending
  end

  private

  # @rbs return: void
  def claim
    raise BusyError, 'a prompt is already running on this Runtime' if @busy
    raise ClosedError, 'this Runtime is closed' if @closed

    @busy = true
    @claim_depth += 1
    @claim_thread = Thread.current
  end

  # Rebuild is a configuration swap at a quiet boundary, not a turn entry, so
  # it may run nested under the thread that holds the Runtime — the /reload
  # command and the automatic reload check both do. Another thread is still
  # refused while work runs.
  # @rbs return: void
  def claim_rebuild
    raise BusyError, 'a prompt is already running on this Runtime' if @busy && @claim_thread != Thread.current
    raise ClosedError, 'this Runtime is closed' if @closed

    @busy = true
    @claim_depth += 1
    @claim_thread = Thread.current
  end

  # @rbs return: void
  def release
    @claim_depth -= 1
    return if @claim_depth.positive?

    @busy = false
    @claim_thread = nil
  end

  # @rbs model: String
  # @rbs config: Riffer::Agent::Config
  # @rbs session: Riffer::Agent::Session?
  # @rbs return: Riffer::Agent
  def build_agent(model, config, session: nil)
    Riffer::Agent.new(session: session, context: { cancel_flag: @cancel_flag, cwd: @cwd, model: model }, config: config)
  end

  # @rbs model: String
  # @rbs config: Riffer::Agent::Config
  # @rbs return: Riffer::Agent
  def successor(model, config)
    agent = build_agent(model, config, session: @agent.session)
    agent.context.token_usage = @agent.context.token_usage
    reactivate(agent.context.skills, activated_skills)
    agent
  end

  # The options the settings built for the starting model are provider-shaped
  # (cache control, per-provider reasoning levels), so a switch re-derives them.
  # Runs after the successor is built, so a failed build leaves the running
  # agent's options alone; riffer reads config.model_options per request, so the
  # swap still reaches the new agent through the shared config.
  # @rbs model: String
  # @rbs return: void
  def rederive_options(model)
    reasoning = Riffer::Rig::Settings::Document.new(@settings).reasoning
    @model_options = Riffer::Rig::Settings.model_options(model, reasoning).merge(native_options(model))
    @agent.config.model_options = @model_options
  end

  # The switches are on/off settings, so what the agent can do stays a function
  # of the current provider: a switch whose provider cannot take the option
  # contributes nothing, and a switch to such a provider drops it, both silently.
  # @rbs model: String
  # @rbs return: Hash[Symbol, untyped]
  def native_options(model)
    provider = Riffer::Rig::Settings.provider_for(model)&.to_sym
    @native_tools.filter_map do |tool, switch|
      next unless provider && NATIVE_TOOLS_BY_PROVIDER[tool]&.key?(provider)

      [tool, switch]
    end.to_h
  end

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs hooks: Riffer::Rig::Runtime::Hooks
  # @rbs max_steps: Numeric?
  # @rbs return: Riffer::Agent::Config
  def agent_config(registrars, hooks, max_steps)
    config = Riffer::Agent::Config.new(
      model: ->(context) { context[:model] },
      model_options: @model_options,
      instructions: system_prompt([]),
      tools_config: select_tools(registrars.flat_map { |registrar| registrar.tools.to_a }.to_h.values, @tool_allowlist),
      max_steps: max_steps,
      tool_runtime: Riffer::Rig::Runtime::ToolRuntime.new(hooks),
      skills_config: skills_config(registrars.flat_map(&:skill_sources))
    )
    config.add_guardrail(:before, klass: Riffer::Rig::Runtime::RequestGuardrail, options: { hooks: hooks })
    # Upstream candidate: riffer resolves MCP tools inside the agent, after
    # tools_config, so the tools: allowlist never sees them.
    config.add_mcp(mcp_tag, progressive: false)
    config
  end

  # @rbs sources: Array[^(Riffer::Rig::Runtime) -> Riffer::Skills::Backend]
  # @rbs return: Riffer::Skills::Config?
  def skills_config(sources)
    return if sources.empty?

    config = Riffer::Skills::Config.new
    config.backend(Riffer::Rig::Skills::Sources.new(sources.map { |source| source.call(self) }))
    config
  end

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs mcp_servers: Hash[String, Riffer::Rig::Mcp::Server]
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs hooks: Riffer::Rig::Runtime::Hooks
  # @rbs agent: Riffer::Agent
  # @rbs return: void
  def install(registrars, mcp_servers, settings, hooks, agent)
    overrides(registrars).each { |message| @host.notify(message, level: :info) }
    @mcp_servers = mcp_servers
    @declared_settings = registrars.to_h { |registrar| [registrar.extension, registrar.declared_settings] }
                                   .reject { |_extension, declared| declared.empty? }
    @settings = with_declared_defaults(settings)
    @prompts = registrars.flat_map { |registrar| registrar.prompts.to_a }.to_h
    skills = agent.context.skills&.skills&.values || []
    commands = [
      *@core_commands,
      Riffer::Rig::Commands::Auth.command,
      Riffer::Rig::Commands::Model.command,
      *skills.map { |skill| Riffer::Rig::Commands::Skill.command(skill) },
      *registrars.flat_map { |registrar| registrar.commands.values }
    ]
    @commands = commands.to_h { |command| [command.name, command] }
    @hooks = hooks
    @agent = agent
  end

  # A session that has not started yet opens with session_start(:new) on its
  # first turn instead.
  # @rbs name: Symbol
  # @rbs event: Riffer::Rig::Events::_Event
  # @rbs return: void
  def lifecycle(name, event)
    return if @session_start_pending

    @hooks.observe(name, event)
    @host.queue(event)
  end

  # @rbs text: String
  # @rbs return: Enumerator[Riffer::StreamEvents::Base, Riffer::Agent::Response]
  def start_turn(text)
    @cancel_flag.clear
    @reload_check&.call(self)
    refresh_system_message
    prompt = @hooks.before_prompt(text)
    return blocked_turn(prompt.reason) if prompt.is_a?(Riffer::Rig::Runtime::Blocked)

    stream = @agent.stream(prompt)
    # Upstream candidate: riffer adds the prompt to the session silently, so
    # its on_message never sees the user message a store has to keep.
    deliver(@agent.session.messages.last)
    stream
  end

  # @rbs reason: String
  # @rbs return: Enumerator[Riffer::StreamEvents::Base, Riffer::Agent::Response]
  def blocked_turn(reason)
    response = Riffer::Agent::Response.new(
      '',
      outcome: Riffer::Agent::Outcome.new(reason: :guardrail_blocked, detail: reason),
      messages: @agent.session.messages.dup.freeze
    )
    Enumerator.new { |_yielder| response }
  end

  # @rbs name: String
  # @rbs args: String
  # @rbs emit: ^(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void
  # @rbs return: void
  def execute(name, args, emit)
    command = @commands.fetch(name, nil)
    return @host.notify("Unknown command: #{name}", level: :error) unless command

    begin
      command.call(command_context(command, args, emit))
    rescue StandardError => e
      @host.notify("Command #{name} failed: #{e.message}", level: :error)
    end
  end

  # @rbs command: Riffer::Rig::Command
  # @rbs args: String
  # @rbs emit: ^(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void
  # @rbs return: Riffer::Rig::Command::Context
  def command_context(command, args, emit)
    settings = @settings[command.extension.to_sym] || {} #: Hash[Symbol, untyped]
    Riffer::Rig::Command::Context.new(
      command.name,
      args,
      runtime: self,
      host: @host,
      settings: settings,
      emit: emit,
      turn: ->(text) { turn(text).each(&emit) }
    )
  end

  # @rbs text: String
  # @rbs return: Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event, Riffer::Agent::Response]
  def turn(text)
    Enumerator.new do |yielder|
      if @session_start_pending
        @session_start_pending = false
        session_start = Riffer::Rig::Events::SessionStart.new(@id, @session_start_reason)
        @hooks.observe(:session_start, session_start)
        yielder << session_start
      end
      @host.drain.each { |queued| yielder << queued }
      response = start_turn(text).each { |event| pass_through(yielder, event) }
      turn_end = Riffer::Rig::Events::TurnEnd.new(stop_reason(response.outcome), response.token_usage)
      @hooks.observe(:turn_end, turn_end)
      @host.drain.each { |queued| yielder << queued }
      yielder << turn_end
      response
    end
  end

  # @rbs yielder: Enumerator::Yielder
  # @rbs event: ::Riffer::StreamEvents::Base
  # @rbs return: void
  def pass_through(yielder, event)
    @hooks.observe(:stream, event)
    yielder << event
    # Mid-turn notifies (a failing hook, a blocked request) reach the stream
    # next to the event that raised them, not at the next turn.
    @host.drain.each { |queued| yielder << queued }
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def observe_message(message)
    deliver(message)
    interrupt_if_cancelled
    case message
    when Riffer::Messages::Assistant
      @hooks.observe(:after_response, Riffer::Rig::Events::AfterResponse.new(message))
    when Riffer::Messages::Tool
      before_next_request if @agent.session.pending_tool_calls.last.empty?
    end
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def deliver(message)
    @message_observers.each { |observer| observer.call(message) }
  end

  # @rbs return: void
  def before_next_request
    @reload_check&.call(self)
    messages = @agent.session.messages
    # Upstream candidate: riffer has no hook between tool results and the next
    # request, so the last tool result's on_message stands in for one.
    verdict = @hooks.before_request(messages)
    return @agent.interrupt!(verdict.reason) if verdict.is_a?(Riffer::Rig::Runtime::Blocked)

    @agent.session.set(verdict.dup) unless verdict.equal?(messages)
  end

  # @rbs return: void
  def interrupt_if_cancelled
    return unless @cancel_flag.set?

    @agent.session.discard_pending_tool_calls
    # Upstream candidate: a cancel token on riffer's run loop. Until then the
    # loop can only be stopped from inside, at a message boundary.
    @agent.interrupt!(INTERRUPT_CANCELLED)
  end

  # @rbs outcome: Riffer::Agent::Outcome
  # @rbs return: Symbol
  def stop_reason(outcome)
    # Upstream candidate: riffer's outcome vocabulary is closed, so a cancel
    # reaches us as :interrupted with the reason in detail.
    cancelled = outcome.reason == :interrupted && outcome.detail == INTERRUPT_CANCELLED.to_s
    cancelled ? INTERRUPT_CANCELLED : outcome.reason
  end

  # @rbs snapshot: Hash[Symbol, untyped]
  # @rbs model: String
  # @rbs config: Riffer::Agent::Config
  # @rbs return: Riffer::Agent
  def restore(snapshot, model, config)
    @model_override = restorable_model(snapshot.fetch(:model), model)
    # Upstream candidate: riffer's Serializer carries an agent's config, never
    # its history, so this and to_h round-trip the session message by message;
    # a Session.from_h could also heal orphaned tool calls on load.
    messages = snapshot.fetch(:messages).map { |message| Riffer::Messages::Base.from_hash(message) }
    session = Riffer::Agent::Session.new(messages: messages)
    session.discard_pending_tool_calls
    agent = build_agent(@model_override || model, config, session: session)
    agent.context.token_usage = usage_of(messages)
    reactivate(agent.context.skills, snapshot.fetch(:skills))
    agent
  end

  # @rbs saved: String?
  # @rbs model: String
  # @rbs return: String?
  def restorable_model(saved, model)
    return nil unless saved

    provider = saved.split('/', 2).first.to_s
    return saved if @credentials.key?(provider.to_sym)

    @host.notify("Not restoring model #{saved}: #{provider} has no credentials; using #{model}", level: :warning)
    nil
  end

  # @rbs messages: Array[Riffer::Messages::Base]
  # @rbs return: Riffer::Providers::TokenUsage?
  def usage_of(messages)
    # Upstream candidate: a nil-aware TokenUsage.sum, which riffer's own
    # Agent::Run and evals also hand-roll; a loaded session could restore its
    # own tally.
    messages.filter_map { |message| message.token_usage if message.is_a?(Riffer::Messages::Assistant) }
            .reduce { |total, usage| total + usage } # rubocop:disable Performance/Sum -- TokenUsage has no zero, and no usage must stay nil
  end

  # @rbs skills: Riffer::Skills::Context?
  # @rbs names: Array[String]
  # @rbs return: void
  def reactivate(skills, names)
    return unless skills

    names.select { |name| skills.skills.key?(name) }.each { |name| skills.activate(name) }
  end

  # @rbs return: Array[String]
  def activated_skills
    # Upstream candidate: Skills::Context keeps its activated list private, so
    # the catalog is filtered through activated? instead.
    skills = @agent.context.skills
    skills ? skills.skills.keys.select { |name| skills.activated?(name) } : []
  end

  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs &: (Riffer::Rig::Extension, StandardError) -> void
  # @rbs return: Array[Riffer::Rig::Registrar]
  def build_registrars(extensions, settings)
    extensions.filter_map do |extension|
      registrar = Riffer::Rig::Registrar.new(extension.name, settings[extension.name.to_sym] || {})
      error = extension.load_into(registrar)
      next registrar unless error

      yield(extension, error)
      nil
    end
  end

  # @rbs extension: Riffer::Rig::Extension
  # @rbs error: StandardError
  # @rbs return: void
  def record_error(extension, error)
    @errors << Riffer::Rig::Extension::Failure.new(extension: extension, error: error)
    @host.notify("Extension #{extension.name} failed to load: #{error.message}", level: :error)
  end

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs return: Array[String]
  def overrides(registrars)
    registrars
      .flat_map { |registrar| registrar.registrations.map { |registration| [registration, registrar.extension] } }
      .group_by(&:first)
      .flat_map do |registration, claims|
        claims.map(&:last).each_cons(2).map do |earlier, later|
          "Extension #{later} replaces #{registration} from #{earlier}"
        end
      end
  end

  # @rbs settings: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped]
  def with_declared_defaults(settings)
    namespaces = @declared_settings.to_h do |extension, defaults|
      given = settings[extension.to_sym] || {} #: Hash[Symbol, untyped]
      [extension.to_sym, defaults.merge(given)]
    end
    settings.merge(namespaces)
  end

  # @rbs return: Hash[Symbol, Array[^(Riffer::Rig::Events::_Event | ::Riffer::StreamEvents::Base) -> untyped]]
  def merge_hooks(registrars)
    Riffer::Rig::Registrar::EVENTS.to_h do |event|
      [event, registrars.flat_map { |registrar| registrar.hooks.fetch(event) }]
    end
  end

  # Upstream candidate: riffer's MCP registry is process-wide and keyed by
  # server name alone, so each Runtime tags its registrations, and two
  # Runtimes declaring the same name replace each other's.
  # @rbs return: Symbol
  def mcp_tag
    :"riffer_rig_#{@id}"
  end

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs return: Hash[String, Riffer::Rig::Mcp::Server]
  def register_mcp_servers(registrars)
    declarations = registrars.flat_map { |registrar| registrar.mcp_servers.to_a }.to_h
    declarations.filter_map do |name, declaration|
      resolved = resolve_declaration(name, declaration)
      next nil unless resolved

      live = @mcp_servers[name]
      server = live && live.declaration == resolved ? live : register_mcp_server(name, resolved)
      [name, server] if server
    end.to_h
  end

  # The stored declaration is the resolved one, so a rebuild compares resolved
  # headers and re-registers when the credentials changed.
  # @rbs name: String
  # @rbs declaration: Riffer::Rig::Mcp::Declaration
  # @rbs return: Riffer::Rig::Mcp::Declaration?
  def resolve_declaration(name, declaration)
    return declaration if declaration.auth.empty?

    values = Riffer::Rig::Mcp::Auth.resolve(name, declaration.auth, host: @host, env: @env, auth_path: @auth_path)
    declaration.with_headers(Riffer::Rig::Mcp::Auth.expand(declaration.headers, values))
  rescue Riffer::Rig::Mcp::Auth::Error => e
    @host.notify("MCP server #{name} failed to register: #{e.message}", level: :error)
    nil
  end

  # @rbs name: String
  # @rbs declaration: Riffer::Rig::Mcp::Declaration
  # @rbs return: Riffer::Rig::Mcp::Server?
  def register_mcp_server(name, declaration)
    registration = @mcp_registry.register(
      name: name, endpoint: declaration.url, tags: [mcp_tag], discovery_headers: declaration.headers
    )
    Riffer::Rig::Mcp::Server.new(declaration: declaration, registration: registration)
  rescue StandardError => e
    @host.notify("MCP server #{name} failed to register: #{e.message}", level: :error)
    nil
  end

  # A retired registration was replaced under the same name, by another
  # Runtime or a later declaration, and is no longer this Runtime's to remove.
  # @rbs servers: Hash[String, Riffer::Rig::Mcp::Server]
  # @rbs return: void
  def unregister_mcp_servers(servers)
    servers.each { |name, server| @mcp_registry.unregister(name) unless server.registration.retired? }
  end

  # @rbs registered: Array[singleton(Riffer::Tool)]
  # @rbs allowlist: Array[String]?
  # @rbs return: Array[singleton(Riffer::Tool)]
  def select_tools(registered, allowlist)
    return registered if allowlist.nil?

    registered.select { |klass| allowlist.include?(klass.name) }
  end

  # @rbs return: void
  def refresh_system_message
    # Upstream candidate: riffer resolves `instructions` once, in Agent.new, so
    # a per-turn system message has to be swapped into the session by hand.
    session = @agent.session
    session.set([Riffer::Messages::System.new(system_prompt(rendered_sections)), *session.messages.drop(1)])
  end

  # @rbs return: Array[String]
  def rendered_sections
    @prompts.each_value.map { |section| section.call(self).to_s }.reject(&:empty?)
  end

  # @rbs sections: Array[String]
  # @rbs return: String
  def system_prompt(sections)
    [@base_prompt, *sections, "Current date: #{Date.today}\nCurrent working directory: #{@cwd}"].join("\n\n")
  end
end
