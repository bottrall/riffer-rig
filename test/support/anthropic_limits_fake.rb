# frozen_string_literal: true

class AnthropicLimitsFake
  attr_reader :looked_up #: Array[String]

  # @rbs limits: Hash[String, Integer]
  # @rbs return: void
  def initialize(limits = {})
    @limits = limits
    @looked_up = []
  end

  # @rbs model_id: String
  # @rbs return: Integer?
  def max_tokens(model_id)
    @looked_up << model_id
    @limits[model_id]
  end
end
