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

  # Per turn, so a job that starts jobs cannot keep a turn alive forever.
  MAX_JOB_CONTINUATIONS = 5 #: Integer

  # @rbs @agent: Riffer::Agent
  # @rbs @cancel_flag: Riffer::Rig::Runtime::CancelFlag
  # @rbs @abort: Riffer::Rig::Runtime::Abort
  # @rbs @draft: Array[String]
  # @rbs @job_inbox: Riffer::Rig::Runtime::JobInbox
  # @rbs @jobs: Riffer::Rig::Runtime::Jobs
  # @rbs @credentials: Hash[Symbol, Hash[Symbol, String]]
  # @rbs @cwd: String
  # @rbs @host: Riffer::Rig::Hosts::Mirror
  # @rbs @id: String
  # @rbs @settings: Hash[Symbol, untyped]
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
  # @rbs @declared_settings: Hash[Symbol, Hash[Symbol, untyped]]
  # @rbs @errors: Array[Riffer::Rig::Extension::Failure]
  # @rbs @hooks: Riffer::Rig::Runtime::Hooks
  # @rbs @tool_allowlist: Array[String]?
  # @rbs @mcp: Riffer::Rig::Runtime::McpRegistrar
  # @rbs @model_options: Hash[Symbol, untyped]
  # @rbs @native_tools: Hash[Symbol, untyped]
  # @rbs @reload_check: (^(::Riffer::Rig::Runtime) -> void)?
  # @rbs @clock: ^() -> Float
  # @rbs @yielder: Enumerator::Yielder?

  # @dynamic agent, credentials, cwd, host, id, settings, declared_settings
  attr_reader :agent #: Riffer::Agent
  attr_reader :credentials #: Hash[Symbol, Hash[Symbol, String]]
  attr_reader :cwd #: String
  attr_reader :host #: Riffer::Rig::Hosts::Mirror
  attr_reader :id #: String
  attr_reader :settings #: Hash[Symbol, untyped]
  attr_reader :declared_settings #: Hash[Symbol, Hash[Symbol, untyped]]

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
    reasoning: nil,
    riffer_config: Riffer.config,
    mcp_registry: Riffer::Mcp,
    max_steps: DEFAULT_MAX_STEPS,
    model_options: {},
    native_tools: {},
    clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
    snapshot: nil
  )
    saved = snapshot && Riffer::Rig::Runtime::Snapshot.from_h(snapshot)
    # Doubles as the snapshot id and ACP sessionId.
    @id = saved ? saved.id : ::SecureRandom.uuid_v7
    @host = Riffer::Rig::Hosts::Mirror.new(host)
    @cwd = cwd || Dir.pwd
    @credentials = credentials

    @concurrency = Riffer::Rig::Runtime::Concurrency.new
    @core_commands = []
    @reload_check = nil
    @clock = clock
    @yielder = nil
    @cancel_flag = Riffer::Rig::Runtime::CancelFlag.new
    @abort = Riffer::Rig::Runtime::Abort.new
    @job_inbox = Riffer::Rig::Runtime::JobInbox.new(clock: clock)
    @jobs = Riffer::Rig::Runtime::Jobs.new(@job_inbox, clock: clock)
    @session_start_pending = true
    @session_start_reason = saved ? :restore : :new
    @message_observers = []
    @model_observers = []
    @reasoning_observers = []
    @reasoning = (saved && Riffer::Rig::Settings::ModelOptions.reasoning_level(saved.reasoning)) || reasoning
    @errors = []
    @tool_allowlist = tools
    @native_tools = native_tools
    @model_options = model_options.merge(Riffer::Rig::Settings::ModelOptions.native_options(model, native_tools))
    @system_prompt = Riffer::Rig::Runtime::SystemPrompt.new(
      instructions || format(BASE_PROMPT_TEMPLATE, name: name), @cwd
    )
    @mcp = Riffer::Rig::Runtime::McpRegistrar.new(
      @id, registry: mcp_registry, host: @host, env: env, auth_path: auth_path
    )
    registrars = build_registrars(extensions, settings) { |extension, error| record_error(extension, error) }
    mcp_servers = @mcp.register(mcp_declarations(registrars))
    hooks = Riffer::Rig::Runtime::Hooks.new(merge_hooks(registrars), @host)
    config = agent_config(registrars, settings, hooks, max_steps)
    agent = saved ? restore(saved, model, config) : build_agent(model, config)
    install(registrars, settings, hooks, agent)
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

  # @rbs return: String?
  def reasoning
    reasoning_over(@settings)
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
      registrars = build_registrars(extensions, settings) { |_extension, error| raise error }
      mcp_servers = @mcp.register(mcp_declarations(registrars))
      hooks = Riffer::Rig::Runtime::Hooks.new(merge_hooks(registrars), @host)
      agent = successor(model, agent_config(registrars, settings, hooks, @agent.config.max_steps))
      lifecycle(:session_end, Riffer::Rig::Events::SessionEnd.new(:reload))
      @errors = []
      install(registrars, settings, hooks, agent)
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
    @jobs.list.count(&:active?)
  end

  # @rbs return: bool
  def busy?
    @concurrency.busy?
  end

  # @rbs return: bool
  def pending_jobs?
    # Jobs stay listed from their start until the model is told of their exit.
    @jobs.list.any?
  end

  # @rbs timeout: Numeric?
  # @rbs return: bool
  def await_job_exit(timeout: nil)
    @job_inbox.await(timeout)
  end

  # @rbs return: Integer
  def pending_job_exit_count
    @job_inbox.size
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

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs hooks: Riffer::Rig::Runtime::Hooks
  # @rbs max_steps: Numeric?
  # @rbs return: Riffer::Agent::Config
  def agent_config(registrars, settings, hooks, max_steps)
    config = Riffer::Agent::Config.new(
      model: ->(context) { context[:model] },
      model_options: @model_options,
      instructions: @system_prompt.bare,
      reasoning: reasoning_over(settings),
      tools_config: select_tools(registrars.flat_map { |registrar| registrar.tools.to_a }.to_h.values, @tool_allowlist),
      max_steps: max_steps,
      tool_runtime: Riffer::Rig::Runtime::ToolRuntime.new(hooks, emit: ->(event) { emit(event) }, clock: @clock),
      skills_config: skills_config(registrars.flat_map(&:skill_sources))
    )
    config.add_guardrail(:before, klass: Riffer::Rig::Runtime::RequestGuardrail, options: { hooks: hooks })
    # Upstream candidate: riffer resolves MCP tools inside the agent, after
    # tools_config, so the tools: allowlist never sees them.
    config.add_mcp(@mcp.tag, progressive: false)
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
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs hooks: Riffer::Rig::Runtime::Hooks
  # @rbs agent: Riffer::Agent
  # @rbs return: void
  def install(registrars, settings, hooks, agent)
    overrides(registrars).each { |message| @host.notify(message, level: :info) }
    unknown_tools(registrars, @tool_allowlist).each { |message| @host.notify(message, level: :warning) }
    @declared_settings = registrars.to_h { |registrar| [registrar.extension.to_sym, registrar.declared_settings] }
                                   .reject { |_extension, declared| declared.empty? }
    @settings = with_declared_defaults(settings)
    @system_prompt = @system_prompt.with_sections(registrars.flat_map { |registrar| registrar.prompts.to_a }.to_h)
    skills = agent.context.skills&.skills&.values || []
    commands = [
      *@core_commands,
      Riffer::Rig::Commands::Auth.command,
      Riffer::Rig::Commands::Model.command,
      Riffer::Rig::Commands::Reasoning.command,
      Riffer::Rig::Commands::Cost.command,
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

    notify_job_exits
    stream = @agent.stream(prompt)
    # Upstream candidate: riffer adds the prompt to the session silently, so
    # its on_message never sees the user message a store has to keep.
    deliver(@agent.session.messages.last)
    stream
  end

  # @rbs return: Enumerator[Riffer::StreamEvents::Base, Riffer::Agent::Response]
  def start_follow_up
    open_turn
    notify_job_exits(follow_up: true) ? @agent.stream : ended_turn(Riffer::Agent::Outcome.new(reason: :completed))
  end

  # @rbs return: void
  def open_turn
    @cancel_flag.clear
    @draft = []
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
    settings = @settings[command.extension] || {} #: Hash[Symbol, untyped]
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
      @yielder = yielder
      if @session_start_pending
        @session_start_pending = false
        session_start = Riffer::Rig::Events::SessionStart.new(@id, @session_start_reason)
        @hooks.observe(:session_start, session_start)
        yielder << session_start
      end
      @host.drain.each { |queued| yielder << queued }
      response = @abort.window do
        stream = Thread.handle_interrupt(Riffer::Rig::Runtime::Abort::SHIELD, &)
        continued(yielder, relay(yielder, stream), MAX_JOB_CONTINUATIONS)
      end
      response ||= aborted(yielder)
      stop_reason = Riffer::Rig::Runtime::StopReason.of(response.outcome)
      turn_end = Riffer::Rig::Events::TurnEnd.new(stop_reason, response.token_usage)
      @hooks.observe(:turn_end, turn_end)
      @host.drain.each { |queued| yielder << queued }
      yielder << turn_end
      response
    ensure
      @yielder = nil
    end
  end

  # @rbs yielder: Enumerator::Yielder
  # @rbs stream: Enumerator[Riffer::StreamEvents::Base, Riffer::Agent::Response]
  # @rbs return: Riffer::Agent::Response
  def relay(yielder, stream)
    stream.each do |event|
      Thread.handle_interrupt(Riffer::Rig::Runtime::Abort::SHIELD) { pass_through(yielder, event) }
    end
  end

  # @rbs yielder: Enumerator::Yielder
  # @rbs response: Riffer::Agent::Response
  # @rbs remaining: Integer
  # @rbs return: Riffer::Agent::Response
  def continued(yielder, response, remaining)
    return response unless remaining.positive? && response.outcome.reason == :completed && steps_left?(response)

    stream = Thread.handle_interrupt(Riffer::Rig::Runtime::Abort::SHIELD) { continuation if notify_job_exits }
    return response unless stream

    continued(yielder, combined(response, relay(yielder, stream)), remaining - 1)
  end

  # @rbs return: Enumerator[::Riffer::StreamEvents::Base, Riffer::Agent::Response]
  def continuation
    @reload_check&.call(self)
    @agent.stream
  end

  # @rbs response: Riffer::Agent::Response
  # @rbs return: bool
  def steps_left?(response)
    max_steps = @agent.config.max_steps
    # Upstream candidate: riffer counts a run's steps from the last user-class
    # message, so a continuation cannot be handed what the turn has left and
    # starts on the full limit.
    max_steps.nil? || response.steps < max_steps
  end

  # @rbs earlier: Riffer::Agent::Response
  # @rbs later: Riffer::Agent::Response
  # @rbs return: Riffer::Agent::Response
  def combined(earlier, later)
    Riffer::Agent::Response.new(
      later.content,
      outcome: later.outcome,
      tripwire: later.tripwire,
      modifications: earlier.modifications + later.modifications,
      reasoning: later.reasoning,
      structured_output: later.structured_output,
      messages: later.messages,
      token_usage: Riffer::Rig::Runtime::Usage.total([earlier.token_usage, later.token_usage]),
      steps: earlier.steps + later.steps
    )
  end

  # The abort unwinds riffer's run loop from outside, so what riffer does for
  # an interrupt it raises itself is done here.
  # @rbs yielder: Enumerator::Yielder
  # @rbs return: Riffer::Agent::Response
  def aborted(yielder)
    @agent.session.discard_pending_tool_calls
    text = @draft.join
    # Silent, then delivered by hand: the on_message observer interrupts a
    # cancelled turn with a throw, and riffer's catch is gone by now.
    deliver(@agent.session.add(Riffer::Messages::Assistant.new(text), silent: true)) if text.match?(/\S/)
    pass_through(yielder, Riffer::StreamEvents::Interrupt.new(reason: Riffer::Rig::Runtime::StopReason::INTERRUPT_CANCELLED))
    Riffer::Agent::Response.new(
      text,
      outcome: Riffer::Agent::Outcome.new(reason: :interrupted, detail: Riffer::Rig::Runtime::StopReason::INTERRUPT_CANCELLED.to_s),
      messages: @agent.session.messages.dup.freeze
    )
  end

  # @rbs yielder: Enumerator::Yielder
  # @rbs event: ::Riffer::StreamEvents::Base
  # @rbs return: void
  def pass_through(yielder, event)
    @draft << event.content if event.is_a?(Riffer::StreamEvents::TextDelta)
    @hooks.observe(:stream, event)
    forward(yielder, event)
  end

  # @rbs event: Riffer::Rig::Events::_Event
  # @rbs return: void
  def emit(event)
    yielder = @yielder
    forward(yielder, event) if yielder
  end

  # @rbs yielder: Enumerator::Yielder
  # @rbs event: ::Riffer::StreamEvents::Base | Riffer::Rig::Events::_Event
  # @rbs return: void
  def forward(yielder, event)
    yielder << event
    # Mid-turn notifies (a failing hook, a blocked request) reach the stream
    # next to the event that raised them, not at the next turn.
    @host.drain.each { |queued| yielder << queued }
  end

  # @rbs message: Riffer::Messages::Base
  # @rbs return: void
  def observe_message(message)
    @draft = []
    deliver(message.is_a?(Riffer::Messages::Tool) ? with_job_notice(message) : message)
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

  # @rbs return: Array[Riffer::Rig::Runtime::JobCompletion]
  def job_exits
    @jobs.consume.each { |completion| emit(Riffer::Rig::Events::JobExit.new(completion)) }
  end

  # @rbs message: Riffer::Messages::Tool
  # @rbs return: Riffer::Messages::Tool
  def with_job_notice(message)
    completions = job_exits
    return message if completions.empty?

    # Appended to a tool result because a user message straight after one is
    # consecutive user turns to Bedrock and Gemini, which reject them.
    noticed = Riffer::Messages::Tool.new(
      "#{message.content}\n\n#{Riffer::Rig::Runtime::JobEnvelope.render(completions)}",
      tool_call_id: message.tool_call_id,
      name: message.name,
      id: message.id,
      error: message.error,
      error_type: message.error_type
    )
    # By identity: Session#update finds a result by its call id, which need
    # not be unique within a session.
    @agent.session.set(@agent.session.messages.map { |recorded| recorded.equal?(message) ? noticed : recorded })
    noticed
  end

  # @rbs follow_up: bool
  # @rbs return: Riffer::Messages::Base?
  def notify_job_exits(follow_up: false)
    completions = job_exits
    return if completions.empty?

    notification = Riffer::Rig::Runtime::JobNotification.new(
      Riffer::Rig::Runtime::JobEnvelope.render(completions),
      follow_up_exits: (completions.size if follow_up)
    )
    # Silent, then delivered by hand: the on_message observer interrupts a
    # cancelled turn with a throw, and no riffer run is there to catch it.
    @agent.session.add(notification, silent: true).tap { |message| deliver(message) }
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

  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs &: (Riffer::Rig::Extension, StandardError) -> void
  # @rbs return: Array[Riffer::Rig::Registrar]
  def build_registrars(extensions, settings)
    extensions.filter_map do |extension|
      outcome = extension.trial(settings)
      next outcome if outcome.is_a?(Riffer::Rig::Registrar)

      yield(extension, outcome)
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

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs allowlist: Array[String]?
  # @rbs return: Array[String]
  def unknown_tools(registrars, allowlist)
    return [] if allowlist.nil?

    registered = registrars.flat_map { |registrar| registrar.tools.keys }
    (allowlist - registered).map { |name| "Unknown tool in allowlist: #{name}" }
  end

  # @rbs settings: Hash[Symbol, untyped]
  # @rbs return: Hash[Symbol, untyped]
  def with_declared_defaults(settings)
    namespaces = @declared_settings.to_h do |extension, defaults|
      given = settings[extension] || {} #: Hash[Symbol, untyped]
      [extension, defaults.merge(given)]
    end
    settings.merge(namespaces)
  end

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs return: Hash[Symbol, Array[^(Riffer::Rig::Events::_Event | ::Riffer::StreamEvents::Base) -> untyped]]
  def merge_hooks(registrars)
    Riffer::Rig::Registrar::EVENTS.to_h do |event|
      [event, registrars.flat_map { |registrar| registrar.hooks.fetch(event) }]
    end
  end

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs return: Hash[String, Riffer::Rig::Mcp::Declaration]
  def mcp_declarations(registrars)
    registrars.flat_map { |registrar| registrar.mcp_servers.to_a }.to_h
  end

  # @rbs registered: Array[singleton(Riffer::Tool)]
  # @rbs allowlist: Array[String]?
  # @rbs return: Array[singleton(Riffer::Tool)]
  def select_tools(registered, allowlist)
    return registered if allowlist.nil?

    registered.select { |klass| allowlist.include?(klass.name) }
  end
end
