# frozen_string_literal: true

module Riffer::Rig::Runtime::Usage
  extend self

  # @rbs messages: Array[Riffer::Messages::Base]
  # @rbs return: Riffer::Providers::TokenUsage?
  def sum(messages)
    # Upstream candidate: a nil-aware TokenUsage.sum, which riffer's own
    # Agent::Run and evals also hand-roll.
    messages.filter_map { |message| message.token_usage if message.is_a?(Riffer::Messages::Assistant) }
            .reduce { |total, usage| total + usage } # rubocop:disable Performance/Sum -- TokenUsage has no zero, and no usage must stay nil
  end
end
