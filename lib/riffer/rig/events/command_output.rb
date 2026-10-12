# frozen_string_literal: true

class Riffer::Rig::Events::CommandOutput
  extend Riffer::Rig::Support::TypedValue::Schema #[Symbol]
  include Riffer::Rig::Support::TypedValue #[Symbol]

  typed_value :command_output, :command, :text

  # @dynamic command, text
  attr_reader :command #: String
  attr_reader :text #: String

  # @rbs command: String
  # @rbs text: String
  # @rbs return: void
  def initialize(command, text)
    @command = command
    @text = text
    freeze
  end
end
