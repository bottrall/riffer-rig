# frozen_string_literal: true

class Riffer::Rig::Terminal::Session
  # One row of the /resume picker, composed by the sessions collaborator: what
  # the session is and when it last moved.
  # @rbs @id: String
  # @rbs @title: String
  # @rbs @updated: Time?
  # @rbs @cwd: String

  # @dynamic id, title, updated, cwd
  attr_reader :id #: String
  attr_reader :title #: String
  attr_reader :updated #: Time?
  attr_reader :cwd #: String

  # @rbs id: String
  # @rbs title: String
  # @rbs updated: Time?
  # @rbs cwd: String
  # @rbs return: void
  def initialize(id:, title:, updated:, cwd:)
    @id = id
    @title = title
    @updated = updated
    @cwd = cwd
    freeze
  end
end
