# frozen_string_literal: true

module Riffer::Rig::Bundled
  Skills = Riffer::Rig::Extension.new('skills') do |rig|
    rig.skills do |runtime|
      Riffer::Skills::FilesystemBackend.new(*Riffer::Rig::Skills.directories(runtime.cwd))
    end
    rig.prompt(:skills) { nil }
  end #: Riffer::Rig::Extension
end
