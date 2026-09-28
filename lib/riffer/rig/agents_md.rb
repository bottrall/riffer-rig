# frozen_string_literal: true

module Riffer::Rig::AgentsMd
  extend self

  FRAMING = 'The user wrote the following instructions in AGENTS.md files, ordered from the most general to ' \
            'the one closest to the working directory. Follow them; where they conflict with the guidance ' \
            'above, they take precedence, and where they conflict with each other, the later file wins.' #: String

  # @rbs cwd: String
  # @rbs return: Array[String]
  def paths(cwd)
    global  = File.join(Dir.home, '.riffer', 'AGENTS.md')
    project = ancestors(File.expand_path(cwd)).reverse.map { |dir| File.join(dir, 'AGENTS.md') }
    [global, *project].uniq.select { |path| File.file?(path) }
  end

  # @rbs cwd: String
  # @rbs return: String?
  def section(cwd)
    blocks = paths(cwd).map { |path| block(path) }
    [FRAMING, *blocks].join("\n\n") unless blocks.empty?
  end

  private

  # @rbs dir: String
  # @rbs return: Array[String]
  def ancestors(dir)
    parent = File.dirname(dir)
    parent == dir ? [dir] : [dir, *ancestors(parent)]
  end

  # @rbs path: String
  # @rbs return: String
  def block(path)
    "<project_instructions path=\"#{path}\">\n#{File.read(path)}\n</project_instructions>"
  end
end
