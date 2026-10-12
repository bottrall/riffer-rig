# frozen_string_literal: true

module Riffer::Rig::Bundled
  Bash = Riffer::Rig::Extension.new('bash') do |rig|
    rig.tool Riffer::Rig::Tools::Bash
    rig.tool Riffer::Rig::Tools::Bash::Poll
    rig.tool Riffer::Rig::Tools::Bash::Kill
  end #: Riffer::Rig::Extension
end
