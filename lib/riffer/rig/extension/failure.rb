# frozen_string_literal: true

class Riffer::Rig::Extension::Failure
  # @dynamic extension, error
  attr_reader :extension #: Riffer::Rig::Extension
  attr_reader :error #: StandardError

  # @rbs extension: Riffer::Rig::Extension
  # @rbs error: StandardError
  # @rbs return: void
  def initialize(extension:, error:)
    @extension = extension
    @error = error
    freeze
  end
end
