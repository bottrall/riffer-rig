# frozen_string_literal: true

require 'fileutils'

class Riffer::Rig::Tools::Write < Riffer::Tool
  identifier 'write'
  description 'Write content to a file, creating it (and any parent directories) or overwriting it.'

  params do
    required :path, String, description: 'Path to the file (absolute, or relative to the working directory)'
    required :content, String, description: 'The full content to write to the file'
  end

  # @rbs context: Riffer::Agent::Context?
  # @rbs path: String
  # @rbs content: String
  # @rbs return: Riffer::Tools::Response
  def call(context:, path:, content:)
    resolved = File.expand_path(path, Dir.pwd)
    FileUtils.mkdir_p(File.dirname(resolved))
    File.write(resolved, content)

    text("Wrote #{content.bytesize} bytes to #{path}")
  end
end
