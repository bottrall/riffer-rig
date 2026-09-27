# frozen_string_literal: true

module Riffer::Rig::Tools::WorkingDirectory
  # @rbs context: Riffer::Agent::Context?
  # @rbs return: String
  def self.of(context)
    cwd = context&.[](:cwd) #: String?
    # Falls back to the process directory for an agent that is not a
    # Runtime's and so hands its tools no :cwd.
    cwd || Dir.pwd
  end

  # @rbs path: String
  # @rbs context: Riffer::Agent::Context?
  # @rbs return: String
  def self.expand(path, context)
    File.expand_path(path, of(context))
  end
end
