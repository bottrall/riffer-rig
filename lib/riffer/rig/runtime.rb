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
  # @rbs @prompts: Hash[Symbol, ^(Riffer::Rig::Runtime) -> String?]
  # @rbs @commands: Hash[String, Riffer::Rig::Command]
  # @rbs @errors: Array[{ extension: Riffer::Rig::Extension, error: StandardError }]

  # @dynamic agent, credentials, cwd, host, id, settings
  attr_reader :agent #: Riffer::Agent
  attr_reader :credentials #: Hash[Symbol, Hash[Symbol, String]]
  attr_reader :cwd #: String
  attr_reader :host #: Riffer::Rig::Hosts::Mirror
  attr_reader :id #: String
  attr_reader :settings #: Hash[Symbol, untyped]

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
    @id = ::SecureRandom.uuid_v7
    @host = Riffer::Rig::Hosts::Mirror.new(host)
    @cwd = cwd || Dir.pwd
    @settings = settings
    @credentials = credentials

    @busy = false
    @closed = false
    @cancel_flag = Riffer::Rig::Runtime::CancelFlag.new
    @session_start_pending = true
    Riffer::Rig::Settings::Pricing.register(pricing, riffer_config.pricing)
    @errors = []
    registrars = build_registrars(extensions)
    overrides(registrars).each { |message| @host.notify(message, level: :info) }
    @prompts = registrars.flat_map { |registrar| registrar.prompts.to_a }.to_h
    commands = [Riffer::Rig::Commands::Model.command, *registrars.flat_map { |registrar| registrar.commands.values }]
    @commands = commands.to_h { |command| [command.name, command] }
    tool_classes = select_tools(registrars.flat_map { |registrar| registrar.tools.to_a }.to_h.values, tools)
    @base_prompt = instructions || format(BASE_PROMPT_TEMPLATE, name: name)

    @agent = build_agent(
      model,
      Riffer::Agent::Config.new(
        model: ->(context) { context[:model] },
        instructions: system_prompt([]),
        tools_config: tool_classes,
        max_steps: max_steps
      )
    )
    @agent.session.on_message { |_message| interrupt_if_cancelled }
  end

  # @rbs text: String
  # @rbs &block: ?(::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event) -> void
  # @rbs return: (nil | Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event, Riffer::Agent::Response])
  def prompt(text, &block)
    claim
    begin
      if block
        wrap_stream(start_turn(text)).each(&block)
        nil
      else
        wrap_stream(start_turn(text))
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
      start_turn(text).each { |event| event }
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
    agent = build_agent(model, @agent.config, session: @agent.session)
    agent.context.token_usage = @agent.context.token_usage
    @agent = agent
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
    # TODO: emit Riffer::Rig::Events::SessionEnd once the rebuild ticket settles
    # the stream's session_end reasons.
    @closed = true
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

  # @rbs text: String
  # @rbs return: Enumerator[Riffer::StreamEvents::Base, Riffer::Agent::Response]
  def start_turn(text)
    @cancel_flag.clear
    refresh_system_message
    @agent.stream(text)
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
      turn: ->(text) { wrap_stream(start_turn(text)).each(&emit) }
    )
  end

  # @rbs stream: Enumerator[Riffer::StreamEvents::Base, Riffer::Agent::Response]
  # @rbs return: Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event, Riffer::Agent::Response]
  def wrap_stream(stream)
    Enumerator.new do |yielder|
      yielder << Riffer::Rig::Events::SessionStart.new(@id, :new) if @session_start_pending
      @session_start_pending = false
      @host.drain.each { |event| yielder << event }
      response = stream.each { |event| yielder << event }
      yielder << Riffer::Rig::Events::TurnEnd.new(stop_reason(response.outcome), response.token_usage)
      response
    end
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

  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs return: Array[Riffer::Rig::Registrar]
  def build_registrars(extensions)
    raise BusyError, 'a prompt is already running on this Runtime' if @busy

    extensions.filter_map do |extension|
      registrar = Riffer::Rig::Registrar.new(extension.name)
      error = load_extension(extension, registrar)
      next registrar unless error

      record_error(extension, error)
      nil
    end
  end

  # @rbs extension: Riffer::Rig::Extension
  # @rbs registrar: Riffer::Rig::Registrar
  # @rbs return: StandardError?
  def load_extension(extension, registrar)
    mismatch = extension.mismatch
    return mismatch if mismatch

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
