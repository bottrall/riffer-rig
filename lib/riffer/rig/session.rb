# frozen_string_literal: true
# rbs_inline: enabled

require 'date'
require 'securerandom'

# The runtime: one Session builds its own Riffer::Agent from a per-instance
# Riffer::Agent::Config and streams a prompt.
#
#   session = Riffer::Rig::Session.new(model: 'mock/x')
#   session.prompt('hello') { |event| ... }   # yields riffer StreamEvents
#   session.prompt('hello').each { |event| }  # an Enumerator without a block
#
# Two Sessions in one process share nothing but the process-wide extension
# registry and riffer's provider repository. One prompt runs at a time; a
# second while one is running raises Riffer::Rig::Session::BusyError. The
# Session never renders, never prints, never reads the filesystem.
class Riffer::Rig::Session
  # Raised when a second prompt or registrar build runs while one is already
  # running on this Session.
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

  attr_reader :agent, :cwd, :host, :settings # : Riffer::Agent # : String # : untyped # : Hash[Symbol, untyped]

  # @rbs @busy: bool

  # : (
  #    String,
  #    ?extensions: Array[Riffer::Rig::Extension],
  #    ?tools: Array[String]?,
  #    ?settings: Hash[Symbol, untyped],
  #    ?host: untyped,
  #    ?cwd: String?,
  #    ?name: String,
  #    ?instructions: String?
  #  ) -> void
  def initialize(
    model,
    extensions: [],
    tools: nil,
    settings: {},
    host: Riffer::Rig::Host.new,
    cwd: nil,
    name: DEFAULT_NAME,
    instructions: nil
  )
    @host = host
    @cwd = cwd || Dir.pwd
    @settings = settings

    @busy = false
    @registrar = build_registrar(extensions)
    tool_classes = select_tools(@registrar.tools, tools)
    base_prompt = instructions || format(BASE_PROMPT_TEMPLATE, name: name)

    @agent = Riffer::Agent.new(config: Riffer::Agent::Config.new(
      model: model,
      instructions: system_prompt(base_prompt),
      tools_config: tool_classes
    ))
  end

  # : (String) { (untyped) -> void } -> nil
  # : (String) -> Enumerator[untyped, void]
  def prompt(text, &block)
    raise BusyError, 'a prompt is already running on this Session' if @busy

    @busy = true
    stream = @agent.stream(text)
    block ? stream.each(&block) : stream
  ensure
    @busy = false
  end

  private

  # : (Array[Riffer::Rig::Extension], Array[String]?) -> Riffer::Rig::Registrar
  def build_registrar(extensions)
    raise BusyError, 'a prompt is already running on this Session' if @busy

    extensions.each_with_object(Riffer::Rig::Registrar.new) do |extension, registrar|
      extension.run(registrar)
    end
  end

  # : (Array[singleton(Riffer::Tool)], Array[String]?) -> Array[singleton(Riffer::Tool)]
  def select_tools(registered, allowlist)
    return registered if allowlist.nil?

    registered.select { |klass| allowlist.include?(klass.name) }
  end

  # : (String) -> String
  def system_prompt(base_prompt)
    "#{base_prompt}\n\nCurrent date: #{Date.today}\nCurrent working directory: #{@cwd}"
  end
end
