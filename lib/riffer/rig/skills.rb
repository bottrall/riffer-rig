# frozen_string_literal: true

module Riffer::Rig::Skills
  extend self

  # @rbs cwd: String
  # @rbs return: Array[String]
  def directories(cwd)
    project = Riffer::Rig::Directories.up_to_repo_root(cwd).map { |dir| File.join(dir, '.agents', 'skills') }
    [*project, File.join(Dir.home, '.agents', 'skills')]
  end
end
