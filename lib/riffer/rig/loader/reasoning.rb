# frozen_string_literal: true

module Riffer::Rig::Loader::Reasoning
  extend self

  # @rbs flag: String?
  # @rbs env: String?
  # @rbs return: String?
  def forced(flag, env)
    flag || env
  end

  # @rbs flag: String?
  # @rbs env: String?
  # @rbs return: String?
  def rejection(flag, env)
    level = forced(flag, env)
    return unless level

    rejection = Riffer::Rig::Settings::ModelOptions.reasoning_rejection(level)
    return unless rejection

    flag ? rejection : "RIFFER_REASONING: #{rejection}"
  end
end
