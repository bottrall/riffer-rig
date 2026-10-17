# frozen_string_literal: true

module Riffer::Rig::Terminal::JobExitNotice
  extend self

  # @rbs exits: Integer
  # @rbs return: String
  def call(exits)
    "#{exits} background #{exits == 1 ? 'job' : 'jobs'} exited"
  end
end
