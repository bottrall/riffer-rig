# frozen_string_literal: true

class Riffer::Rig::Terminal::Builtin
  # @dynamic name, description
  attr_reader :name #: String
  attr_reader :description #: String

  # @rbs name: String
  # @rbs description: String
  # @rbs return: void
  def initialize(name, description:)
    @name = name
    @description = description
    freeze
  end
end
