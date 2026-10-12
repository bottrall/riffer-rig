# frozen_string_literal: true

require 'acp/sdk'
require 'securerandom'

class Riffer::Rig::ACP::Host
  include Riffer::Rig::Hosts::NonInteractive

  CAPABILITIES = Set[:notify, :ask, :confirm].freeze #: Set[Symbol]
  BUILDING_CAPABILITIES = Set[:notify].freeze #: Set[Symbol]

  # @rbs @client: ::ACP::AgentConnection::_Client
  # @rbs @session_id: String?
  # @rbs @buffered: Array[String]

  # @rbs client: ::ACP::AgentConnection::_Client
  # @rbs return: void
  def initialize(client:)
    @client = client
    @session_id = nil
    @buffered = []
  end

  # A request to the client names its session, and the client learns the id
  # of a new one only from the session/new reply, so nothing can be relayed
  # while that session is still building.
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
    id = @session_id
    return @buffered << message.to_s unless id

    send_update(id, message.to_s)
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
    @session_id = id
    buffered = @buffered
    @buffered = []
    buffered.each { |message| send_update(id, message) }
  end

  private

  # @rbs id: String
  # @rbs question: String
  # @rbs options: Array[::ACP::Types::PermissionOption]
  # @rbs return: String?
  def permit(id, question, options)
    request = Riffer::Rig::ACP::Mapper.permission_request(id, SecureRandom.uuid, question, options)
    Riffer::Rig::ACP::Mapper.selected_option(@client.request_permission(request))
  end

  # @rbs id: String
  # @rbs question: String
  # @rbs return: String?
  def elicit(id, question)
    request = Riffer::Rig::ACP::Mapper.elicitation_request(id, question)
    Riffer::Rig::ACP::Mapper.elicited_answer(@client.create_elicitation(request))
  end

  # @rbs id: String
  # @rbs message: String
  # @rbs return: void
  def send_update(id, message)
    @client.update(
      id,
      ::ACP::Types::SessionUpdate::AgentMessageChunk.new(
        content: ::ACP::Types::ContentBlock::Text.new(text: message)
      )
    )
  end
end
