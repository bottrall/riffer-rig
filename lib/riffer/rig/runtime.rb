# frozen_string_literal: true

require 'date'
require 'securerandom'

# Runs prompts on its own Riffer::Agent, streaming events or returning the
# response. It never renders, prints or reads the filesystem: anything a host
# needs is a Runtime feature, so embedders get it too.
class Riffer::Rig::Runtime
  # Raised when a prompt or ask starts while another is running.
  class BusyError < StandardError; end

  # Raised when a prompt or ask is sent to a closed Runtime.
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

  # @rbs @agent: Riffer::Agent
  # @rbs @credentials: Hash[Symbol, Hash[Symbol, String]]
  # @rbs @cwd: String
  # @rbs @host: _Host
  # @rbs @id: String
  # @rbs @notifier: Riffer::Rig::NotifyingHost
  # @rbs @settings: Hash[Symbol, untyped]
  # @rbs @busy: bool
  # @rbs @closed: bool
  # @rbs @session_start_pending: bool
  # @rbs @registrar: Riffer::Rig::Registrar

  # @dynamic agent, credentials, cwd, settings
  attr_reader :agent #: Riffer::Agent
  attr_reader :credentials #: Hash[Symbol, Hash[Symbol, String]]
  attr_reader :cwd #: String
  attr_reader :settings #: Hash[Symbol, untyped]

  # Returns the given host, wrapped so every notify is mirrored onto the stream.
  #
  # @dynamic host
  attr_reader :host #: _Host

  # Returns the UUIDv7 minted at construction; also the snapshot id and ACP
  # sessionId.
  #
  # @dynamic id
  attr_reader :id #: String

  # Builds the agent, running each extension's block against a fresh registrar.
  #
  # @rbs model: String
  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs tools: Array[String]?
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs host: _Host
  # @rbs cwd: String?
  # @rbs name: String
  # @rbs instructions: String?
  # @rbs credentials: Hash[Symbol, Hash[Symbol, String]]
  # @rbs pricing: Hash[String, Riffer::Rig::Settings::Pricing]
  # @rbs max_steps: Integer?
  # @rbs snapshot: Hash[Symbol, untyped]?
  # @rbs return: void
  def initialize(
    model,
    extensions: [],
    tools: nil,
    settings: {},
    host: Riffer::Rig::Host.new,
    cwd: nil,
    name: DEFAULT_NAME,
    instructions: nil,
    credentials: {},
    pricing: {},
    max_steps: DEFAULT_MAX_STEPS,
    snapshot: nil
  )
    @id = ::SecureRandom.uuid_v7
    @notifier = Riffer::Rig::NotifyingHost.new(host)
    @host = @notifier
    @cwd = cwd || Dir.pwd
    @settings = settings
    @credentials = credentials

    @busy = false
    @closed = false
    @session_start_pending = true
    @registrar = build_registrar(extensions)
    tool_classes = select_tools(@registrar.tools, tools)
    base_prompt = instructions || format(BASE_PROMPT_TEMPLATE, name: name)

    @agent = Riffer::Agent.new(
      config: Riffer::Agent::Config.new(
        model: model,
        instructions: system_prompt(base_prompt),
        tools_config: tool_classes,
        max_steps: max_steps
      )
    )
  end

  # Streams one turn's events to the block, or returns them as an Enumerator
  # when no block is given.
  #
  # @rbs text: String
  # @rbs &block: ?(::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event) -> void
  # @rbs return: (nil | Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event, Riffer::Agent::Response])
  def prompt(text, &block)
    raise BusyError, 'a prompt is already running on this Runtime' if @busy
    raise ClosedError, 'this Runtime is closed' if @closed

    @busy = true
    if block
      wrap_stream(@agent.stream(text)).each(&block)
      nil
    else
      wrap_stream(@agent.stream(text))
    end
  ensure
    @busy = false
  end

  # Runs one turn to completion and returns riffer's response.
  #
  # @rbs text: String
  # @rbs return: Riffer::Agent::Response
  def ask(text)
    raise BusyError, 'a prompt is already running on this Runtime' if @busy
    raise ClosedError, 'this Runtime is closed' if @closed

    @busy = true
    @agent.stream(text).each { |event| event }
  ensure
    @busy = false
  end

  # Refuses further prompts and asks.
  #
  # @rbs return: void
  def close
    # TODO: emit Riffer::Rig::Events::SessionEnd once the rebuild ticket settles
    # the stream's session_end reasons.
    @closed = true
  end

  private

  # @rbs stream: Enumerator[Riffer::StreamEvents::Base, Riffer::Agent::Response]
  # @rbs return: Enumerator[::Riffer::StreamEvents::Base | Riffer::Rig::Events::Event, Riffer::Agent::Response]
  def wrap_stream(stream)
    Enumerator.new do |yielder|
      yielder << Riffer::Rig::Events::SessionStart.new(@id, :new) if @session_start_pending
      @session_start_pending = false
      @notifier.drain.each { |event| yielder << event }
      response = stream.each { |event| yielder << event }
      yielder << Riffer::Rig::Events::TurnEnd.new(response.outcome.reason, response.token_usage)
      response
    end
  end

  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs return: Riffer::Rig::Registrar
  def build_registrar(extensions)
    raise BusyError, 'a prompt is already running on this Runtime' if @busy

    extensions.each_with_object(Riffer::Rig::Registrar.new) do |extension, registrar|
      extension.run(registrar)
    end
  end

  # @rbs registered: Array[singleton(Riffer::Tool)]
  # @rbs allowlist: Array[String]?
  # @rbs return: Array[singleton(Riffer::Tool)]
  def select_tools(registered, allowlist)
    return registered if allowlist.nil?

    registered.select { |klass| allowlist.include?(klass.name) }
  end

  # @rbs base_prompt: String
  # @rbs return: String
  def system_prompt(base_prompt)
    "#{base_prompt}\n\nCurrent date: #{Date.today}\nCurrent working directory: #{@cwd}"
  end
end
