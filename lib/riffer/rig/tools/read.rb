# frozen_string_literal: true

class Riffer::Rig::Tools::Read < Riffer::Tool
  identifier 'read'
  description 'Read a file from the filesystem. Returns its contents with line numbers. ' \
              'Use offset/limit to read a slice of a large file.'

  DEFAULT_LIMIT = 2000 #: Integer

  params do
    required :path, String, description: 'Path to the file (absolute, or relative to the working directory)'
    optional :offset, Integer, description: '1-based line number to start reading from'
    optional :limit, Integer, description: 'Maximum number of lines to read', default: DEFAULT_LIMIT
  end

  # @rbs context: Riffer::Agent::Context?
  # @rbs path: String
  # @rbs ?offset: Integer?
  # @rbs ?limit: Integer
  # @rbs return: Riffer::Tools::Response
  def call(context:, path:, offset: nil, limit: DEFAULT_LIMIT)
    resolved = File.expand_path(path, Dir.pwd)
    return error("File not found: #{path}", type: :not_found) unless File.file?(resolved)
    return error('offset must be >= 1', type: :invalid_argument) if offset && offset < 1

    start = offset ? offset - 1 : 0
    lines = File.readlines(resolved, chomp: true)
    slice = lines[start, limit] || []

    numbered = slice.each_with_index.map do |line, i|
      format("%<lineno>6d\t%<text>s", lineno: start + i + 1, text: line)
    end

    text(numbered.join("\n"))
  end
end
