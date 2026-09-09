# frozen_string_literal: true

class Riffer::Rig::Tools::Edit < Riffer::Tool
  identifier 'edit'
  description 'Replace an exact string in a file. By default old_string must occur exactly once; ' \
              'set replace_all to replace every occurrence.'

  params do
    required :path, String, description: 'Path to the file (absolute, or relative to the working directory)'
    required :old_string, String, description: 'The exact text to replace'
    required :new_string, String, description: 'The text to replace it with'
    optional :replace_all, Riffer::Params::Boolean, description: 'Replace all occurrences instead of requiring a unique match', default: false
  end

  # @rbs context: Riffer::Agent::Context?
  # @rbs path: String
  # @rbs old_string: String
  # @rbs new_string: String
  # @rbs ?replace_all: bool
  # @rbs return: Riffer::Tools::Response
  def call(context:, path:, old_string:, new_string:, replace_all: false)
    resolved = File.expand_path(path, Dir.pwd)
    return error("File not found: #{path}", type: :not_found) unless File.file?(resolved)

    content = File.read(resolved)
    occurrences = content.scan(old_string).length

    return error("old_string not found in #{path}", type: :not_found) if occurrences.zero?
    return error("old_string is not unique in #{path} (#{occurrences} matches). Pass replace_all or add more context.", type: :ambiguous_match) if occurrences > 1 && !replace_all

    # Block form so backslash sequences in new_string (\0, \1, \\) are inserted
    # literally instead of being interpreted as regexp backreferences.
    updated = replace_all ? content.gsub(old_string) { new_string } : content.sub(old_string) { new_string }
    File.write(resolved, updated)

    text("Edited #{path} (#{replace_all ? occurrences : 1} replacement#{'s' if replace_all && occurrences > 1})")
  end
end
