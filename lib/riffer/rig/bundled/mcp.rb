# frozen_string_literal: true

module Riffer::Rig::Bundled
  Mcp = Riffer::Rig::Extension.new('mcp') do |rig|
    rig.settings[:servers].to_h.each do |name, server|
      rig.mcp(
        name.to_s,
        url: server.fetch(:url),
        headers: server[:headers].to_h.transform_keys(&:to_s),
        auth: Hash(server[:auth])
      )
    end
  end #: Riffer::Rig::Extension
end
