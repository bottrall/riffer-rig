# frozen_string_literal: true

class Riffer::Rig::Hosts::Null
  include Riffer::Rig::Hosts::NonInteractive

  # @rbs return: Set[Symbol]
  def capabilities
    Set.new.freeze
  end

  # @rbs message: String?
  # @rbs level: Symbol
  # @rbs return: void
  def notify(message = nil, level: :info)
    nil
  end
end
