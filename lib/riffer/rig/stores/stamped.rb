# frozen_string_literal: true

# @rbs module-self Riffer::Rig::Stores::_Stamped
module Riffer::Rig::Stores::Stamped
  # @rbs return: Time?
  def recorded_time
    Riffer::Rig::Stores::Timestamp.load(recorded_at)
  end
end
