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
  # @rbs @prompts: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  # @rbs @commands: Hash[String, Riffer::Rig::Command]
  # @rbs @declared_settings: Hash[String, Hash[Symbol, untyped]]
  # @rbs @errors: Array[{ extension: Riffer::Rig::Extension, error: StandardError }]
  # @rbs @hooks: Riffer::Rig::Runtime::Hooks
  # @rbs @tool_allowlist: Array[String]?

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
  # @rbs host: Riffer::Rig::Hosts::Base
  # @rbs cwd: String?
  # @rbs name: String
  # @rbs instructions: String?
  # @rbs credentials: Hash[Symbol, Hash[Symbol, String]]
  # @rbs pricing: Hash[String, Riffer::Rig::Settings::Pricing]
  # @rbs riffer_config: Riffer::Config
  # @rbs max_steps: Integer?
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
    pricing: {},
    riffer_config: Riffer.config,
    max_steps: DEFAULT_MAX_STEPS,
    snapshot: nil
  )
    # Doubles as the snapshot id and ACP sessionId.
    @id = snapshot ? snapshot.fetch(:id) : ::SecureRandom.uuid_v7
    @host = Riffer::Rig::Hosts::Mirror.new(host)
    @cwd = cwd || Dir.pwd
    @credentials = credentials

    @busy = false
    @closed = false
    @cancel_flag = Riffer::Rig::Runtime::CancelFlag.new
    @session_start_pending = true
    @session_start_reason = snapshot ? :restore : :new
    @message_observers = []
    Riffer::Rig::Settings::Pricing.register(pricing, riffer_config.pricing)
    @errors = []
    @tool_allowlist = tools
    @base_prompt = instructions || format(BASE_PROMPT_TEMPLATE, name: name)
    registrars = build_registrars(extensions) { |extension, error| record_error(extension, error) }
    hooks = Riffer::Rig::Runtime::Hooks.new(merge_hooks(registrars), @host)
    config = agent_config(registrars, hooks, max_steps)
    install(registrars, settings, hooks, snapshot ? restore(snapshot, model, config) : build_agent(model, config))
    @agent.session.on_message { |message| observe_message(message) }
  end

  # @rbs text: String
  # @rbs &block: ?(::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event) -> void
  # @rbs return: (nil | Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event, Riffer::Agent::Response])
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
      @busy = false
    end
  end

  # @rbs text: String
  # @rbs return: Riffer::Agent::Response
  def ask(text)
    claim
    begin
      turn(text).each { |event| event }
    ensure
      @busy = false
    end
  end

  # @rbs return: Array[Riffer::Rig::Command]
  def commands
    @commands.values
  end

  # @rbs name: String
  # @rbs args: String
  # @rbs &block: ?(::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event) -> void
  # @rbs return: nil
  def run_command(name, args = '', &block)
    claim
    emit = block || ->(_event) {} #: ^(::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event) -> void
    begin
      execute(name, args, emit)
    ensure
      @busy = false
    end
    @host.drain.each(&emit)
    nil
  end

  # @rbs return: Array[{ extension: Riffer::Rig::Extension, error: StandardError }]
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
    @agent = successor(model, @agent.config)
    @model_override = model
  end

  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs return: nil
  def rebuild(extensions:, settings:)
    claim
    begin
      registrars = build_registrars(extensions) { |_extension, error| raise error }
      hooks = Riffer::Rig::Runtime::Hooks.new(merge_hooks(registrars), @host)
      agent = successor(model, agent_config(registrars, hooks, @agent.config.max_steps))
      lifecycle(:session_end, Riffer::Rig::Events::SessionEnd.new(:reload))
      @errors = []
      install(registrars, settings, hooks, agent)
      lifecycle(:session_start, Riffer::Rig::Events::SessionStart.new(@id, :reload))
    ensure
      @busy = false
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
    @hooks.observe(:session_end, Riffer::Rig::Events::SessionEnd.new(:close)) unless @session_start_pending
  end

  private

  # @rbs return: void
  def claim
    raise BusyError, 'a prompt is already running on this Runtime' if @busy
    raise ClosedError, 'this Runtime is closed' if @closed

    @busy = true
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

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs hooks: Riffer::Rig::Runtime::Hooks
  # @rbs max_steps: Numeric?
  # @rbs return: Riffer::Agent::Config
  def agent_config(registrars, hooks, max_steps)
    config = Riffer::Agent::Config.new(
      model: ->(context) { context[:model] },
      instructions: system_prompt([]),
      tools_config: select_tools(registrars.flat_map { |registrar| registrar.tools.to_a }.to_h.values, @tool_allowlist),
      max_steps: max_steps,
      tool_runtime: Riffer::Rig::Runtime::ToolRuntime.new(hooks),
      skills_config: skills_config(registrars.flat_map(&:skill_sources))
    )
    config.add_guardrail(:before, klass: Riffer::Rig::Runtime::RequestGuardrail, options: { hooks: hooks })
    config
  end

  # @rbs sources: Array[^(Riffer::Rig::Runtime) -> Riffer::Skills::Backend]
  # @rbs return: Riffer::Skills::Config?
  def skills_config(sources)
    return if sources.empty?

    config = Riffer::Skills::Config.new
    config.backend(Riffer::Rig::Runtime::SkillSources.new(sources.map { |source| source.call(self) }))
    config
  end

  # @rbs registrars: Array[Riffer::Rig::Registrar]
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs hooks: Riffer::Rig::Runtime::Hooks
  # @rbs agent: Riffer::Agent
  # @rbs return: void
  def install(registrars, settings, hooks, agent)
    overrides(registrars).each { |message| @host.notify(message, level: :info) }
    @declared_settings = registrars.to_h { |registrar| [registrar.extension, registrar.settings] }
                                   .reject { |_extension, declared| declared.empty? }
    @settings = with_declared_defaults(settings)
    @prompts = registrars.flat_map { |registrar| registrar.prompts.to_a }.to_h
    skills = agent.context.skills&.skills&.values || []
    commands = [
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
  # @rbs event: Riffer::Rig::Events::Event
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
  # @rbs emit: ^(::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event) -> void
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
  # @rbs emit: ^(::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event) -> void
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
  # @rbs return: Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event, Riffer::Agent::Response]
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
    # Upstream candidate: TokenUsage has no zero to seed sum with, and no usage
    # at all must stay nil; a loaded session could restore its own tally.
    messages.filter_map { |message| message.token_usage if message.is_a?(Riffer::Messages::Assistant) }
            .reduce { |total, usage| total + usage } # rubocop:disable Performance/Sum
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
  # @rbs &: (Riffer::Rig::Extension, StandardError) -> void
  # @rbs return: Array[Riffer::Rig::Registrar]
  def build_registrars(extensions)
    extensions.filter_map do |extension|
      registrar = Riffer::Rig::Registrar.new(extension.name)
      error = load_extension(extension, registrar)
      next registrar unless error

      yield(extension, error)
      nil
    end
  end

  # @rbs extension: Riffer::Rig::Extension
  # @rbs registrar: Riffer::Rig::Registrar
  # @rbs return: StandardError?
  def load_extension(extension, registrar)
    rejection = extension.mismatch || registrar.collision
    return rejection if rejection

    extension.run(registrar)
    nil
  rescue StandardError => e
    e
  end

  # @rbs extension: Riffer::Rig::Extension
  # @rbs error: StandardError
  # @rbs return: void
  def record_error(extension, error)
    @errors << { extension: extension, error: error }
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

  # @rbs return: Hash[Symbol, Array[^(Riffer::Rig::Events::Event | ::Riffer::StreamEvents::Base) -> untyped]]
  def merge_hooks(registrars)
    Riffer::Rig::Registrar::EVENTS.to_h do |event|
      [event, registrars.flat_map { |registrar| registrar.hooks.fetch(event) }]
    end
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
