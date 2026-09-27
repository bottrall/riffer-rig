# frozen_string_literal: true

module Riffer::Rig::AgentsMd
  extend self

  FRAMING = 'The user wrote the following instructions in AGENTS.md files. Follow them; ' \
            'where they conflict with the guidance above, they take precedence.' #: String

  # @rbs cwd: String
  # @rbs return: Array[String]
  def paths(cwd)
    [File.join(Dir.home, '.riffer', 'AGENTS.md'), File.join(cwd, 'AGENTS.md')].select { |path| File.file?(path) }
  end

  # @rbs cwd: String
  # @rbs return: String?
  def section(cwd)
    blocks = paths(cwd).map { |path| block(path) }
    [FRAMING, *blocks].join("\n\n") unless blocks.empty?
  end

  private

  # @rbs path: String
  # @rbs return: String
  def block(path)
    "<project_instructions path=\"#{path}\">\n#{File.read(path)}\n</project_instructions>"
  end
end
