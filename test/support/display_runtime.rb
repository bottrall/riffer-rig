# frozen_string_literal: true

class DisplayRuntime
  attr_reader :tally, :cancels

  def initialize(tally: nil, on_cancel: -> {})
    @tally = tally
    @on_cancel = on_cancel
    @cancels = 0
  end

  def model = 'mock/test'

  def cancel
    @cancels += 1
    @on_cancel.call
  end
end
