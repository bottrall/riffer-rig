# frozen_string_literal: true

require 'date'

# One Runtime builds its own Riffer::Agent from a per-instance
# Riffer::Agent::Config and runs a prompt: streamed, or gathered into a Turn.
#
#   runtime = Riffer::Rig::Runtime.new('mock/x')
#   runtime.prompt('hello') { |event| ... }   # yields riffer StreamEvents
#   runtime.prompt('hello').each { |event| }  # an Enumerator without a block
#   turn = runtime.ask('hello')               # a Riffer::Rig::Turn
#
# Two Runtimes in one process share nothing but the process-wide extension
# registry and riffer's provider repository. One prompt runs at a time; a
# second while one is running raises Riffer::Rig::Runtime::BusyError. The
# Runtime never renders, never prints, never reads the filesystem.
class Riffer::Rig::Runtime
  # Raised when a second prompt, ask or registrar build runs while one is
  # already running on this Runtime.
  class BusyError < StandardError; end

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

  # @rbs!
  #   interface _Host
  #     def ask: (?String, ?options: Array[String]?, ?secret: bool) -> String?
  #     def confirm: (?String) -> bool
  #     def notify: (?String, ?level: Symbol) -> void
  #     def progress: (?String) { () -> void } -> void
  #     def capabilities: () -> Set[Symbol]
  #   end

  # @rbs @agent: Riffer::Agent
  # @rbs @cwd: String
  # @rbs @host: _Host
  # @rbs @settings: Hash[Symbol, untyped]
  # @rbs @busy: bool
  # @rbs @registrar: Riffer::Rig::Registrar

  # @dynamic agent, cwd, host, settings
  attr_reader :agent #: Riffer::Agent
  attr_reader :cwd #: String
  attr_reader :host #: _Host
  attr_reader :settings #: Hash[Symbol, untyped]

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
    @host = host
    @cwd = cwd || Dir.pwd
    @settings = settings

    @busy = false
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
  # @rbs &block: ?(Riffer::StreamEvents::Base) -> void
  # @rbs return: (nil | Enumerator[Riffer::StreamEvents::Base, void])
  def prompt(text, &block)
    raise BusyError, 'a prompt is already running on this Runtime' if @busy

    @busy = true
    if block
      @agent.stream(text).each(&block)
      nil
    else
      @agent.stream(text)
    end
  ensure
    @busy = false
  end

  # @rbs text: String
  # @rbs return: Riffer::Rig::Turn
  def ask(text)
    raise BusyError, 'a prompt is already running on this Runtime' if @busy

    @busy = true
    run_turn(text)
  ensure
    @busy = false
  end

  private

  # @rbs text: String
  # @rbs return: Riffer::Rig::Turn
  def run_turn(text)
    response = @agent.stream(text).each { |event| event }
    Riffer::Rig::Turn.from_response(response)
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
