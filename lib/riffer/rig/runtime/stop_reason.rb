# frozen_string_literal: true

module Riffer::Rig::Runtime::StopReason
  extend self

  INTERRUPT_CANCELLED = :cancelled #: Symbol

  # Riffer's remaining stop reasons (:error, :other, :guardrail_blocked) are
  # failures, not early stops.
  STOPPED_WITHOUT_COMPLETING = %i[
    max_steps context_window length content_filter malformed_output
  ].freeze #: Array[Symbol]

  # @rbs outcome: Riffer::Agent::Outcome
  # @rbs return: Symbol
  def of(outcome)
    # Upstream candidate: riffer's outcome vocabulary is closed, so a cancel
    # reaches us as :interrupted with the reason in detail.
    cancelled = outcome.reason == :interrupted && outcome.detail == INTERRUPT_CANCELLED.to_s
    cancelled ? INTERRUPT_CANCELLED : outcome.reason
  end
end
