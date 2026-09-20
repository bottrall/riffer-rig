# frozen_string_literal: true

require 'date'
require 'securerandom'

# One Runtime builds its own Riffer::Agent from a per-instance
# Riffer::Agent::Config and runs a prompt: streamed as events, or run to
# completion and returned as riffer's Agent::Response.
#
#   runtime = Riffer::Rig::Runtime.new('mock/x')
#   runtime.prompt('hello') { |event| ... }   # yields riffer StreamEvents
#   runtime.prompt('hello').each { |event| }  # an Enumerator without a block
#   response = runtime.ask('hello')           # a Riffer::Agent::Response
#
# Every prompt ends with a rig-level Riffer::Rig::Events::TurnEnd carrying the run's
# stop reason and token usage; construction emits Riffer::Rig::Events::SessionStart and
# close emits Riffer::Rig::Events::SessionEnd. See Riffer::Rig::Events for the vocabulary.
#
# Two Runtimes in one process share nothing but the process-wide extension
# registry and riffer's provider repository. One prompt runs at a time; a
# second while one is running raises Riffer::Rig::Runtime::BusyError. The
# Runtime never renders, never prints, never reads the filesystem.
class Riffer::Rig::Runtime
  # Raised when a second prompt, ask or registrar build runs while one is
  # already running on this Runtime.
  class BusyError < StandardError; end

  # Raised when a prompt or ask is sent to a Runtime that has been closed.
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

  # The legacy CodingAgent's default: an unlimited agent loop. riffer's own
  # default (16) is too small for a general-purpose harness.
  DEFAULT_MAX_STEPS = nil #: Integer?

  # @rbs @agent: Riffer::Agent
  # @rbs @cwd: String
  # @rbs @host: _Host
  # @rbs @id: String
  # @rbs @notifier: Riffer::Rig::NotifyingHost
  # @rbs @settings: Hash[Symbol, untyped]
  # @rbs @busy: bool
  # @rbs @closed: bool
  # @rbs @session_start_pending: bool
  # @rbs @registrar: Riffer::Rig::Registrar

  # @dynamic agent, cwd, host, settings
  attr_reader :agent #: Riffer::Agent
  attr_reader :cwd #: String
  attr_reader :host #: _Host
  attr_reader :settings #: Hash[Symbol, untyped]

  # UUIDv7 minted at construction; also the snapshot id and ACP sessionId.
  #
  # @dynamic id
  attr_reader :id #: String

  # @rbs model: String
  # @rbs extensions: Array[Riffer::Rig::Extension]
  # @rbs tools: Array[String]?
  # @rbs settings: Hash[Symbol, untyped]
  # @rbs host: _Host
  # @rbs cwd: String?
  # @rbs name: String
  # @rbs instructions: String?
  # @rbs credentials: Hash[String, String]
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

  # Queues Riffer::Rig::Events::SessionEnd with reason +:close+ and refuses
  # further prompts and asks.
  #
  # @rbs return: void
  def close
    @closed = true
    @session_start_pending = false
    @notifier.queue(Riffer::Rig::Events::SessionEnd.new(:close))
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
