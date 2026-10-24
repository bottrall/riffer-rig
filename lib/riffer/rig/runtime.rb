# frozen_string_literal: true

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

  DEFAULT_REASONING_LABEL = 'default' #: String

  # Unlimited: riffer's own default (16) is too small for a general-purpose
  # harness.
  DEFAULT_MAX_STEPS = nil #: Integer?

  # @rbs @agent: Riffer::Agent
  # @rbs @cancel_flag: Riffer::Rig::Runtime::CancelFlag
  # @rbs @abort: Riffer::Rig::Runtime::Abort
  # @rbs @job_inbox: Riffer::Rig::Runtime::JobInbox
  # @rbs @jobs: Riffer::Rig::Runtime::Jobs
  # @rbs @job_notices: Riffer::Rig::Runtime::JobNotices
  # @rbs @credentials: Hash[Symbol, Hash[Symbol, String]]
  # @rbs @cwd: String
  # @rbs @host: Riffer::Rig::Hosts::Mirror
  # @rbs @id: String
  # @rbs @concurrency: Riffer::Rig::Runtime::Concurrency
  # @rbs @session_start_pending: bool
  # @rbs @session_start_reason: Symbol
  # @rbs @model_override: String?
  # @rbs @reasoning: String?
  # @rbs @message_observers: Array[^(Riffer::Messages::Base) -> void]
  # @rbs @model_observers: Array[^(String) -> void]
  # @rbs @reasoning_observers: Array[^(String) -> void]
  # @rbs @system_prompt: Riffer::Rig::Runtime::SystemPrompt
  # @rbs @commands: Hash[String, Riffer::Rig::Command]
  # @rbs @core_commands: Array[Riffer::Rig::Command]
  # @rbs @assembly: Riffer::Rig::Runtime::Assembly
  # @rbs @hooks: Riffer::Rig::Runtime::Hooks
  # @rbs @tool_allowlist: Array[String]?
  # @rbs @mcp: Riffer::Rig::Runtime::McpRegistrar
  # @rbs @model_options: Hash[Symbol, untyped]
  # @rbs @native_tools: Hash[Symbol, untyped]
  # @rbs @reload_check: (^(::Riffer::Rig::Runtime) -> void)?
  # @rbs @clock: ^() -> Float
  # @rbs @turn: Riffer::Rig::Runtime::Turn?

  # @dynamic agent, credentials, cwd, host, id
  attr_reader :agent #: Riffer::Agent
  attr_reader :credentials #: Hash[Symbol, Hash[Symbol, String]]
  attr_reader :cwd #: String
  attr_reader :host #: Riffer::Rig::Hosts::Mirror
  attr_reader :id #: String

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
  # @rbs reasoning: String?
  # @rbs riffer_config: Riffer::Config
  # @rbs mcp_registry: Riffer::Rig::Mcp::_Registry
  # @rbs max_steps: Integer?
  # @rbs model_options: Hash[Symbol, untyped]
  # @rbs native_tools: Hash[Symbol, untyped]
  # @rbs clock: ^() -> Float
  # @rbs snapshot: (Riffer::Rig::Runtime::Snapshot | Hash[Symbol, untyped])?
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
    reasoning: nil,
    riffer_config: Riffer.config,
    mcp_registry: Riffer::Mcp,
    max_steps: DEFAULT_MAX_STEPS,
    model_options: {},
    native_tools: {},
    clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
    snapshot: nil
  )
    saved = snapshot && Riffer::Rig::Runtime::Snapshot.of(snapshot)
    # Doubles as the snapshot id and ACP sessionId.
    @id = saved ? saved.id : ::SecureRandom.uuid_v7
    @host = Riffer::Rig::Hosts::Mirror.new(host)
    @cwd = cwd || Dir.pwd
    @credentials = credentials

    @concurrency = Riffer::Rig::Runtime::Concurrency.new
    @core_commands = []
    @reload_check = nil
    @clock = clock
    @turn = nil
    @cancel_flag = Riffer::Rig::Runtime::CancelFlag.new
    @abort = Riffer::Rig::Runtime::Abort.new
    @job_inbox = Riffer::Rig::Runtime::JobInbox.new(clock: clock)
    @jobs = Riffer::Rig::Runtime::Jobs.new(@job_inbox, clock: clock)
    @job_notices = Riffer::Rig::Runtime::JobNotices.new(
      @jobs, @job_inbox, emit: ->(event) { emit(event) }, deliver: ->(message) { deliver(message) }
    )
    @session_start_pending = true
    @session_start_reason = saved ? :restore : :new
    @message_observers = []
    @model_observers = []
    @reasoning_observers = []
    @reasoning = (saved && Riffer::Rig::Settings::ModelOptions.reasoning_level(saved.reasoning)) || reasoning
    @tool_allowlist = tools
    @native_tools = native_tools
    @model_options = model_options.merge(Riffer::Rig::Settings::ModelOptions.native_options(model, native_tools))
    @system_prompt = Riffer::Rig::Runtime::SystemPrompt.new(
      instructions || format(BASE_PROMPT_TEMPLATE, name: name), @cwd
    )
    @mcp = Riffer::Rig::Runtime::McpRegistrar.new(
      @id, registry: mcp_registry, host: @host, env: env, auth_path: auth_path
    )
    assembly = Riffer::Rig::Runtime::Assembly.new(extensions, settings, tools)
    assembly.failures.each do |failure|
      @host.notify("Extension #{failure.extension.name} failed to load: #{failure.error.message}", level: :error)
    end
    mcp_servers = @mcp.register(assembly.mcp_declarations)
    hooks = Riffer::Rig::Runtime::Hooks.new(assembly.hooks, @host)
    config = agent_config(assembly, hooks, max_steps)
    agent = saved ? restore(saved, model, config) : build_agent(model, config)
    install(assembly, hooks, agent)
    @mcp.retain(mcp_servers)
    @agent.session.on_message do |message|
      Thread.handle_interrupt(Riffer::Rig::Runtime::Abort::SHIELD) { observe_message(message) }
    end
  end

  # @rbs text: String
  # @rbs &: ?(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void
  # @rbs return: (nil | Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event, Riffer::Agent::Response])
  def prompt(text, &)
    claimed(turn { start_turn(text) }, &)
  end

  # @rbs &: ?(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void
  # @rbs return: (nil | Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event, Riffer::Agent::Response])
  def follow_up(&)
    claimed(turn { start_follow_up }, &)
  end

  # @rbs text: String
  # @rbs return: Riffer::Agent::Response
  def ask(text)
    @concurrency.claim
    begin
      turn { start_turn(text) }.each { |event| event }
    ensure
      @concurrency.release
    end
  end

  # @rbs return: Array[Riffer::Rig::Command]
  def commands
    @commands.values
  end

  # @rbs command: Riffer::Rig::Command
  # @rbs return: nil
  def install_command(command)
    # Kept apart from the extensions' commands, which a rebuild replaces.
    @core_commands << command
    @commands[command.name] = command
    nil
  end

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
    @concurrency.claim
    emit = block || ->(_event) {} #: ^(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void
    begin
      execute(name, args, emit)
    ensure
      @concurrency.release
    end
    @host.drain.each(&emit)
    nil
  end

  # @rbs return: Array[Riffer::Rig::Extension::Failure]
  def errors
    @assembly.failures.dup
  end

  # @rbs return: Hash[Symbol, untyped]
  def settings
    @assembly.settings
  end

  # @rbs return: Hash[Symbol, Hash[Symbol, untyped]]
  def declared_settings
    @assembly.declared_settings
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

  # @rbs return: String?
  def reasoning
    reasoning_over(settings)
  end

  # @rbs level: String
  # @rbs return: void
  def reasoning=(level)
    # Riffer's own validation raises before anything is assigned, so a level it
    # refuses leaves both the level and the config unchanged.
    @agent.config.reasoning = level
    @reasoning = level
    @reasoning_observers.each { |observer| observer.call(level) }
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
    @concurrency.claim_rebuild
    begin
      assembly = Riffer::Rig::Runtime::Assembly.new(extensions, settings, @tool_allowlist, strict: true)
      mcp_servers = @mcp.register(assembly.mcp_declarations)
      hooks = Riffer::Rig::Runtime::Hooks.new(assembly.hooks, @host)
      agent = successor(model, agent_config(assembly, hooks, @agent.config.max_steps))
      lifecycle(:session_end, Riffer::Rig::Events::SessionEnd.new(:reload))
      install(assembly, hooks, agent)
      @mcp.retain(mcp_servers)
      lifecycle(:session_start, Riffer::Rig::Events::SessionStart.new(@id, :reload))
    ensure
      @concurrency.release
    end
    nil
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    Riffer::Rig::Runtime::Snapshot.new(
      id: @id,
      messages: @agent.session.messages,
      model: @model_override,
      reasoning: @reasoning,
      skills: activated_skills
    ).to_h
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

  # @rbs &block: (String) -> void
  # @rbs return: nil
  def on_reasoning_change(&block)
    @reasoning_observers << block
    nil
  end

  # @rbs &: (Riffer::Rig::Runtime::JobCompletion) -> void
  # @rbs return: nil
  def on_job_exit(&)
    @job_inbox.subscribe(&)
    nil
  end

  # @rbs return: Integer
  def running_job_count
    @job_notices.running_count
  end

  # @rbs return: bool
  def busy?
    @concurrency.busy?
  end

  # @rbs return: bool
  def pending_jobs?
    @job_notices.pending?
  end

  # @rbs timeout: Numeric?
  # @rbs return: bool
  def await_job_exit(timeout: nil)
    @job_notices.await(timeout)
  end

  # @rbs return: Integer
  def pending_job_exit_count
    @job_notices.pending_exit_count
  end

  # @rbs return: nil
  def cancel
    @cancel_flag.set
    @abort.fire
    nil
  end

  # @rbs return: Riffer::Providers::TokenUsage?
  def tally
    @agent.context.token_usage
  end

  # @rbs return: void
  def close
    return if @concurrency.closed?

    @concurrency.close
    @job_inbox.close
    @jobs.shutdown
    @mcp.retain({})
    @hooks.observe(:session_end, Riffer::Rig::Events::SessionEnd.new(:close)) unless @session_start_pending
  end

  private

  # @rbs model: String
  # @rbs config: Riffer::Agent::Config
  # @rbs session: Riffer::Agent::Session?
  # @rbs return: Riffer::Agent
  def build_agent(model, config, session: nil)
    Riffer::Agent.new(
      session: session,
      context: { cancel_flag: @cancel_flag, cwd: @cwd, model: model, jobs: @jobs },
      config: config
    )
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
  # (anthropic cache control), so a switch re-derives them; the reasoning level
  # is provider-agnostic and travels on the config. Runs after the successor is
  # built, so a failed build leaves the running agent's options alone; riffer
  # reads config.model_options per request, so the swap still reaches the new
  # agent through the shared config.
  # @rbs model: String
  # @rbs return: void
  def rederive_options(model)
    options = Riffer::Rig::Settings::ModelOptions
    @model_options = options.model_options(model).merge(options.native_options(model, @native_tools))
    @agent.config.model_options = @model_options
  end

  # @rbs settings: Hash[Symbol, untyped]
  # @rbs return: String?
  def reasoning_over(settings)
    @reasoning || Riffer::Rig::Settings::ModelOptions.reasoning_level(Riffer::Rig::Settings::Document.new(settings).reasoning)
  end

  # @rbs assembly: Riffer::Rig::Runtime::Assembly
  # @rbs hooks: Riffer::Rig::Runtime::Hooks
  # @rbs max_steps: Numeric?
  # @rbs return: Riffer::Agent::Config
  def agent_config(assembly, hooks, max_steps)
    config = Riffer::Agent::Config.new(
      model: ->(context) { context[:model] },
      model_options: @model_options,
      instructions: @system_prompt.bare,
      reasoning: reasoning_over(assembly.settings),
      tools_config: assembly.tools,
      max_steps: max_steps,
      tool_runtime: Riffer::Rig::Runtime::ToolRuntime.new(hooks, emit: ->(event) { emit(event) }, clock: @clock),
      skills_config: assembly.skills_config(self)
    )
    config.add_guardrail(:before, klass: Riffer::Rig::Runtime::RequestGuardrail, options: { hooks: hooks })
    # Upstream candidate: riffer resolves MCP tools inside the agent, after
    # tools_config, so the tools: allowlist never sees them.
    config.add_mcp(@mcp.tag, progressive: false)
    config
  end

  # @rbs assembly: Riffer::Rig::Runtime::Assembly
  # @rbs hooks: Riffer::Rig::Runtime::Hooks
  # @rbs agent: Riffer::Agent
  # @rbs return: void
  def install(assembly, hooks, agent)
    assembly.overrides.each { |message| @host.notify(message, level: :info) }
    assembly.unknown_tools.each { |message| @host.notify(message, level: :warning) }
    @assembly = assembly
    @system_prompt = @system_prompt.with_sections(assembly.prompt_sections)
    @commands = assembly.commands(@core_commands, agent.context.skills&.skills&.values || [])
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

  # @rbs turn: Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event, Riffer::Agent::Response]
  # @rbs &block: ?(::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event) -> void
  # @rbs return: (nil | Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event, Riffer::Agent::Response])
  def claimed(turn, &block)
    @concurrency.claim
    begin
      if block
        turn.each(&block)
        nil
      else
        turn
      end
    ensure
      @concurrency.release
    end
  end

  # @rbs text: String
  # @rbs return: Enumerator[Riffer::StreamEvents::Base, Riffer::Agent::Response]
  def start_turn(text)
    open_turn
    prompt = @hooks.before_prompt(text)
    if prompt.is_a?(Riffer::Rig::Runtime::Blocked)
      return ended_turn(Riffer::Agent::Outcome.new(reason: :guardrail_blocked, detail: prompt.reason))
    end

    @job_notices.notify(@agent.session)
    stream = @agent.stream(prompt)
    # Upstream candidate: riffer adds the prompt to the session silently, so
    # its on_message never sees the user message a store has to keep.
    deliver(@agent.session.messages.last)
    stream
  end

  # @rbs return: Enumerator[Riffer::StreamEvents::Base, Riffer::Agent::Response]
  def start_follow_up
    open_turn
    return @agent.stream if @job_notices.notify(@agent.session, follow_up: true)

    ended_turn(Riffer::Agent::Outcome.new(reason: :completed))
  end

  # @rbs return: void
  def open_turn
    @cancel_flag.clear
    @reload_check&.call(self)
    @system_prompt.refresh(@agent.session, self)
  end

  # @rbs outcome: Riffer::Agent::Outcome
  # @rbs return: Enumerator[Riffer::StreamEvents::Base, Riffer::Agent::Response]
  def ended_turn(outcome)
    response = Riffer::Agent::Response.new('', outcome: outcome, messages: @agent.session.messages.dup.freeze)
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
    settings = self.settings[command.extension] || {} #: Hash[Symbol, untyped]
    Riffer::Rig::Command::Context.new(
      command.name,
      args,
      runtime: self,
      host: @host,
      settings: settings,
      emit: emit,
      turn: ->(text) { turn { start_turn(text) }.each(&emit) }
    )
  end

  # @rbs &: () -> Enumerator[::Riffer::StreamEvents::Base, Riffer::Agent::Response]
  # @rbs return: Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event, Riffer::Agent::Response]
  def turn(&)
    Enumerator.new do |yielder|
      turn = Riffer::Rig::Runtime::Turn.new(
        yielder,
        host: @host,
        abort: @abort,
        agent: -> { @agent },
        hooks: -> { @hooks },
        continuation: -> { continuation if @job_notices.notify(@agent.session) },
        deliver: ->(message) { deliver(message) }
      )
      @turn = turn
      turn.run(session_start, &)
    ensure
      @turn = nil
    end
  end

  # @rbs return: Riffer::Rig::Events::SessionStart?
  def session_start
    return unless @session_start_pending

    @session_start_pending = false
    Riffer::Rig::Events::SessionStart.new(@id, @session_start_reason)
  end

  # @rbs return: Enumerator[::Riffer::StreamEvents::Base, Riffer::Agent::Response]
  def continuation
    @reload_check&.call(self)
    @agent.stream
  end

  # @rbs event: Riffer::Rig::Events::_Event
  # @rbs return: void
  def emit(event)
    @turn&.forward(event)
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def observe_message(message)
    @turn&.clear_draft
    deliver(message.is_a?(Riffer::Messages::Tool) ? @job_notices.with_notice(message, @agent.session) : message)
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
    # The abort is held off while a tool runs, so a cancel that lands there is
    # honoured at the message boundary.
    @agent.interrupt!(Riffer::Rig::Runtime::StopReason::INTERRUPT_CANCELLED)
  end

  # @rbs snapshot: Riffer::Rig::Runtime::Snapshot
  # @rbs model: String
  # @rbs config: Riffer::Agent::Config
  # @rbs return: Riffer::Agent
  def restore(snapshot, model, config)
    @model_override = snapshot.restorable_model(@credentials, @host, model)
    agent = build_agent(@model_override || model, config, session: snapshot.session)
    agent.context.token_usage = snapshot.usage
    reactivate(agent.context.skills, snapshot.skills)
    agent
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
end
