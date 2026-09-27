# frozen_string_literal: true

module Riffer::Rig::Bundled
  Edit = Riffer::Rig::Extension.new('edit') { |rig| rig.tool Riffer::Rig::Tools::Edit } #: Riffer::Rig::Extension
end
