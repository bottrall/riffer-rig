# frozen_string_literal: true

class Riffer::Rig::Hosts::Null < Riffer::Rig::Hosts::Base
  # @rbs return: Set[Symbol]
  def capabilities
    Set.new.freeze
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question = nil, options: nil, secret: false)
    nil
  end

  # @rbs question: String?
  # @rbs return: bool
  def confirm(question = nil)
    false
  end

  # @rbs message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message = nil, level: :info)
    nil
  end

  # @rbs label: String?
  # @rbs &block: ? () -> void
  # @rbs return: void
  def progress(label = nil, &block)
    block&.call
  end
end
