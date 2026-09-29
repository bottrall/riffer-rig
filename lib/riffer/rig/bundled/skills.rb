# frozen_string_literal: true

module Riffer::Rig::Bundled
  Skills = Riffer::Rig::Extension.new('skills') do |rig|
    rig.skills do |runtime|
      project = Riffer::Rig::Directories.up_to_repo_root(runtime.cwd).map { |dir| File.join(dir, '.agents', 'skills') }
      Riffer::Skills::FilesystemBackend.new(*project, File.join(Dir.home, '.riffer', 'skills'))
    end
    rig.prompt(:skills) { nil }
  end #: Riffer::Rig::Extension
end
