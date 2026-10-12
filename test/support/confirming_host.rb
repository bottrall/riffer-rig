# frozen_string_literal: true

require 'forwardable'

class ConfirmingHost
  extend Forwardable

  def_delegators :@null, :progress

  attr_reader :questions #: Array[String?]
  attr_reader :notifications #: Array[[Symbol, String]]

  # @rbs answers: Array[untyped]
  # @rbs return: void
  def initialize(answers = [])
    @null = Riffer::Rig::Hosts::Null.new
    @answers = answers
    @questions = []
    @notifications = []
  end

  # @rbs return: Set[Symbol]
  def capabilities
    Set[:ask, :confirm, :notify]
  end

  # @rbs question: String?
  # @rbs options: Array[untyped]?
  # @rbs secret: bool
  # @rbs return: untyped
  def ask(question = nil, options: nil, secret: false)
    @questions << question
    @answers.shift
  end

  # @rbs question: String?
  # @rbs return: untyped
  def confirm(question = nil)
    @questions << question
    @answers.shift
  end

  # @rbs message: String
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message, level: :info)
    @notifications << [level, message]
  end
end
