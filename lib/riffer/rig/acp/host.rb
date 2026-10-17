# frozen_string_literal: true

require 'acp/sdk'
require 'securerandom'

class Riffer::Rig::ACP::Host
  include Riffer::Rig::Hosts::NonInteractive

  CAPABILITIES = Set[:notify, :ask, :confirm].freeze #: Set[Symbol]
  BUILDING_CAPABILITIES = Set[:notify].freeze #: Set[Symbol]

  # @rbs @client: ::ACP::AgentConnection::Client
  # @rbs @session_id: String?
  # @rbs @buffered: Array[::ACP::Types::SessionUpdate::t]
  # @rbs @lock: Thread::Mutex

  # @dynamic client=
  attr_writer :client #: ::ACP::AgentConnection::Client

  # @rbs client: ::ACP::AgentConnection::Client
  # @rbs return: void
  def initialize(client:)
    @client = client
    @session_id = nil
    @buffered = []
    @lock = Mutex.new
  end

  # A request to the client names its session, so nothing can be relayed
  # until the agent sets the id.
  # @rbs return: Set[Symbol]
  def capabilities
    @session_id ? CAPABILITIES : BUILDING_CAPABILITIES
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question = nil, options: nil, secret: false)
    id = @session_id
    # ACP forbids asking for a secret in a form elicitation, and rig serves no
    # URL for the URL mode to open.
    return super unless id && !secret
    return elicit(id, question.to_s) unless options

    selected = permit(id, question.to_s, Riffer::Rig::ACP::Mapper.choices(options))
    selected if options.include?(selected)
  end

  # @rbs question: String?
  # @rbs return: bool
  def confirm(question = nil)
    id = @session_id
    return super unless id

    permit(id, question.to_s, Riffer::Rig::ACP::Mapper::CONFIRM_OPTIONS) == Riffer::Rig::ACP::Mapper::CONFIRMED
  end

  # @rbs message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message = nil, level: :info)
    update(Riffer::Rig::ACP::Mapper.message_chunk(message.to_s))
  end

  # @rbs update: ::ACP::Types::SessionUpdate::t
  # @rbs return: void
  def update(update)
    # A job's exit reaches here on the job's own thread, racing session_id= for
    # the buffer.
    @lock.synchronize do
      id = @session_id
      id ? @client.update(id, update) : @buffered << update
    end
  end

  # @rbs label: String?
  # @rbs &block: ? () -> void
  # @rbs return: void
  def progress(label = nil, &block)
    notify(label) if label
    block&.call
  end

  # Session updates name their session, and acp-sdk runs session_created after
  # the session/new reply so the client knows the id before any update for it
  # arrives — that is why the build-time notifies wait for this, not for the
  # Runtime's construction to end.
  # @rbs id: String
  # @rbs return: void
  def session_id=(id)
    @lock.synchronize do
      @session_id = id
      @buffered.each { |update| @client.update(id, update) }
      @buffered = []
    end
  end

  private

  # @rbs id: String
  # @rbs question: String
  # @rbs options: Array[::ACP::Types::PermissionOption]
  # @rbs return: String?
  def permit(id, question, options)
    # An adopting connection can replace @client while the question is out, and
    # only the client that was asked knows the tool call to close.
    client = @client
    # A permission request must name a tool call, and a host question has none.
    call_id = SecureRandom.uuid
    client.update(id, Riffer::Rig::ACP::Mapper.permission_call(call_id, question))
    request = Riffer::Rig::ACP::Mapper.permission_request(id, call_id, question, options)
    selected = Riffer::Rig::ACP::Mapper.selected_option(client.request_permission(request))
    client.update(id, Riffer::Rig::ACP::Mapper.permission_done(call_id, selected))
    selected
  end

  # @rbs id: String
  # @rbs question: String
  # @rbs return: String?
  def elicit(id, question)
    request = Riffer::Rig::ACP::Mapper.elicitation_request(id, question)
    Riffer::Rig::ACP::Mapper.elicited_answer(@client.create_elicitation(request))
  end
end
