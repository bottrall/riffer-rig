# frozen_string_literal: true

class Riffer::Rig::Hosts::Base
  # @rbs return: Set[Symbol]
  def capabilities
    raise NotImplementedError, "#{self.class} must implement #{__method__}"
  end

  # @rbs question: String?
  # @rbs options: Array[String]?
  # @rbs secret: bool
  # @rbs return: String?
  def ask(question = nil, options: nil, secret: false)
    raise NotImplementedError, "#{self.class} must implement #{__method__}"
  end

  # @rbs question: String?
  # @rbs return: bool
  def confirm(question = nil)
    raise NotImplementedError, "#{self.class} must implement #{__method__}"
  end

  # @rbs message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message = nil, level: :info)
    raise NotImplementedError, "#{self.class} must implement #{__method__}"
  end

  # @rbs label: String?
  # @rbs &: ? () -> void
  # @rbs return: void
  def progress(label = nil, &)
    raise NotImplementedError, "#{self.class} must implement #{__method__}"
  end
end
