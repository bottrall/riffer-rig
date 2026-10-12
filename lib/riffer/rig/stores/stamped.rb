# frozen_string_literal: true

# @rbs module-self Riffer::Rig::Support::_ToH
module Riffer::Rig::Stores::Stamped
  # @dynamic recorded_at
  attr_reader :recorded_at #: Time?

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    super.merge(recorded_at: Riffer::Rig::Stores::Timestamp.dump(recorded_at)).compact
  end
end
