# frozen_string_literal: true

require 'acp/sdk'

class Riffer::Rig::ACP::Host
  include Riffer::Rig::Hosts::NonInteractive

  CAPABILITIES = Set[:notify].freeze #: Set[Symbol]

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

  # @rbs return: Set[Symbol]
  def capabilities
    CAPABILITIES
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
