# frozen_string_literal: true

module Riffer::Rig::Bundled
  Write = Riffer::Rig::Extension.new('write') { |rig| rig.tool Riffer::Rig::Tools::Write } #: Riffer::Rig::Extension
end
