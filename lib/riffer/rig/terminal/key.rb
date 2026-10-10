# frozen_string_literal: true

class Riffer::Rig::Terminal::Key
  # @dynamic name, text
  attr_reader :name #: Symbol
  attr_reader :text #: String?

  # @rbs name: Symbol
  # @rbs text: String?
  # @rbs return: void
  def initialize(name, text = nil)
    @name = name
    @text = text
    freeze
  end

  # @rbs other: untyped
  # @rbs return: bool
  def ==(other)
    other.class == self.class && other.to_h == to_h
  end

  # @rbs return: Integer
  def hash
    [self.class, to_h].hash
  end

  # @rbs other: untyped
  # @rbs return: bool
  def eql?(other)
    self == other
  end

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    { name: name, text: text }
  end
end
