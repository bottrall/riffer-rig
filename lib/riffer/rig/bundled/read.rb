# frozen_string_literal: true

module Riffer::Rig::Bundled
  Read = Riffer::Rig::Extension.new('read') { |rig| rig.tool Riffer::Rig::Tools::Read } #: Riffer::Rig::Extension
end
