# frozen_string_literal: true

module Riffer::Rig::Bundled
  AgentsMd = Riffer::Rig::Extension.new('agents_md') do |rig|
    rig.prompt(:agents_md) { |runtime| Riffer::Rig::AgentsMd.section(runtime.cwd) }
  end #: Riffer::Rig::Extension
end
