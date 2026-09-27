# frozen_string_literal: true

module Riffer::Rig::Bundled
  Bash = Riffer::Rig::Extension.new('bash') { |rig| rig.tool Riffer::Rig::Tools::Bash } #: Riffer::Rig::Extension
end
