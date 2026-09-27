# frozen_string_literal: true

class Riffer::Rig::Command
  # @rbs @block: ^(Riffer::Rig::Command::Context) -> void

  # @dynamic name, description, extension
  attr_reader :name #: String
  attr_reader :description #: String
  attr_reader :extension #: String

  # @rbs name: String
  # @rbs description: String
  # @rbs extension: String
  # @rbs &block: (Riffer::Rig::Command::Context) -> void
  # @rbs return: void
  def initialize(name, description:, extension:, &block)
    @name = name
    @description = description
    @extension = extension
    @block = block
    freeze
  end

  # @rbs ctx: Riffer::Rig::Command::Context
  # @rbs return: void
  def call(ctx)
    @block.call(ctx)
  end
end
