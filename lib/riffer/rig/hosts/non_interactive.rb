# frozen_string_literal: true

module Riffer::Rig::Hosts::NonInteractive
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

  # @rbs label: String?
  # @rbs &block: ? () -> void
  # @rbs return: void
  def progress(label = nil, &block)
    block&.call
  end
end
