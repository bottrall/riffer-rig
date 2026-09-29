# frozen_string_literal: true

module Riffer::Rig::Directories
  extend self

  # @rbs dir: String
  # @rbs return: Array[String]
  def ancestors(dir)
    parent = File.dirname(dir)
    parent == dir ? [dir] : [dir, *ancestors(parent)]
  end

  # @rbs cwd: String
  # @rbs return: Array[String]
  def up_to_repo_root(cwd)
    dirs = ancestors(File.expand_path(cwd))
    root = dirs.index { |dir| File.exist?(File.join(dir, '.git')) } || 0
    dirs.take(root + 1)
  end
end
