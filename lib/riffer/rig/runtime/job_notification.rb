# frozen_string_literal: true

class Riffer::Rig::Runtime::JobNotification < Riffer::Messages::User
  MARKER = :job_notification #: Symbol

  # @rbs return: Hash[Symbol, untyped]
  def to_h
    super.merge(MARKER => true)
  end
end
